package com.hackasol.scamshield.qa

import com.hackasol.scamshield.ListenerWiring
import com.hackasol.scamshield.NotificationInfo
import com.hackasol.scamshield.VerdictRowMapper
import com.hackasol.scamshield.core.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class QAAlertsPrivacyTest {
    // ---------- Alert policy ----------
    @Test fun `QA_alertPolicy_everyNonSafeVerdictReachesTheUserOnEverySource`() {
        for (src in Source.values()) for (l in listOf(Label.SCAM, Label.SUSPICIOUS)) {
            val p = AlertPolicy.plan(l, src)
            assertTrue("$l/$src silent", p.bubble || p.notify)
            assertEquals(p.bubble || p.notify, p.reportAction)
        }
    }

    @Test fun `QA_alertPolicy_safeIsAlwaysSilent`() {
        for (src in Source.values()) assertEquals(AlertPlan(false, false, false), AlertPolicy.plan(Label.SAFE, src))
    }

    @Test fun `QA_alertPolicy_scamAlwaysNotifiesBubbleOnlyLive`() {
        for (src in Source.values()) {
            val p = AlertPolicy.plan(Label.SCAM, src)
            assertTrue(p.notify); assertEquals(src == Source.CAPTION, p.bubble)
        }
    }

    @Test fun `QA_alertPolicy_suspiciousIsExactlyOneChannel`() {
        for (src in Source.values()) { val p = AlertPolicy.plan(Label.SUSPICIOUS, src); assertNotEquals(p.bubble, p.notify) }
    }

    // ---------- Alert mapper ----------
    private fun fields(v: Verdict, t: ScamType? = null) = AlertNotificationMapper.fields(AlertPolicy.plan(v, Source.SMS), v, t)

    @Test fun `QA_alertMapper_safeAndBubbleOnlyPlansProduceNoNotification`() {
        assertNull(AlertNotificationMapper.fields(AlertPlan(false, false, false), qaVerdict(Label.SAFE, 0.9)))
        assertNull(AlertNotificationMapper.fields(AlertPolicy.plan(Label.SUSPICIOUS, Source.CAPTION), qaVerdict(Label.SUSPICIOUS, 0.5, source = Source.CAPTION)))
        assertNull("SAFE verdict with a forced notify plan must still be silent",
            AlertNotificationMapper.fields(AlertPlan(true, true, true), qaVerdict(Label.SAFE, 0.9)))
    }

    @Test fun `QA_alertMapper_rawMessageBodyNeverAppearsInNotification`() {
        val v = qaVerdict(Label.SCAM, 0.9, text = "RAW-BODY-PRIVATE-123 my account number is 0001", triggers = listOf("otp"))
        val f = fields(v, ScamType.OTP)!!
        assertFalse(f.text.contains("RAW-BODY")); assertFalse(f.title.contains("RAW-BODY"))
    }

    @Test fun `QA_alertMapper_whitespaceOnlyTriggerOmittedAndLongOneCut`() {
        assertFalse(fields(qaVerdict(Label.SCAM, 0.9, triggers = listOf("   ")))!!.text.contains("\"\""))
        val long = fields(qaVerdict(Label.SCAM, 0.9, triggers = listOf("x".repeat(500))))!!
        assertTrue(long.text.length < 200)
    }

    @Test fun `QA_alertMapper_reportActionAlwaysPresentWithReportRoute`() {
        for (l in listOf(Label.SCAM, Label.SUSPICIOUS)) {
            val f = fields(qaVerdict(l, 0.5))!!
            assertEquals(listOf(AlertNotificationMapper.ROUTE_REPORT), f.actions.map { it.route }); assertTrue(f.priorityHigh)
        }
    }

    @Test fun `QA_alertMapper_otherAndNullTypeHaveNoTypePrefix`() {
        val a = fields(qaVerdict(Label.SCAM, 0.9, triggers = listOf("t")), null)!!.text
        val b = fields(qaVerdict(Label.SCAM, 0.9, triggers = listOf("t")), ScamType.OTHER)!!.text
        assertEquals(a, b)
        assertNotEquals(a, fields(qaVerdict(Label.SCAM, 0.9, triggers = listOf("t")), ScamType.OTP)!!.text)
    }

    // ---------- 1930 dialing / manifest / permissions ----------
    private fun mainKotlin() = File(QAPaths.appDir, "src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.toList()

    @Test fun `QA_dial_noProductCodeUsesActionCall`() {
        val offenders = mainKotlin().filter { it.readText().contains("ACTION_CALL") && !it.readText().contains("ACTION_CALL_BUTTON") }
        assertTrue("ACTION_CALL used in $offenders", offenders.isEmpty())
        assertTrue(mainKotlin().any { it.readText().contains("ACTION_DIAL") })
    }

    private fun manifests() = File(QAPaths.appDir, "src").walkTopDown().filter { it.name == "AndroidManifest.xml" }.toList()

    @Test fun `QA_manifest_mainManifestIsResolvable`() {
        assertTrue(File(QAPaths.appDir, "src/main/AndroidManifest.xml").readText().contains("<manifest"))
    }

    @Test fun `QA_manifest_noSmsCallLogContactsOrCallPhonePermissions`() {
        val banned = listOf("READ_SMS", "RECEIVE_SMS", "SEND_SMS", "READ_CALL_LOG", "CALL_PHONE", "READ_CONTACTS", "READ_PHONE_NUMBERS", "ANSWER_PHONE_CALLS")
        for (m in manifests()) { val t = m.readText(); for (b in banned) assertFalse("${m.path} declares $b", t.contains("android.permission.$b")) }
    }

    @Test fun `QA_manifest_notificationListenerIsProtectedByBindPermission`() {
        val t = File(QAPaths.appDir, "src/main/AndroidManifest.xml").readText()
        val svc = t.substringAfter("ScamNotificationListener").substringBefore("</service>")
        assertTrue(svc.contains("android.permission.BIND_NOTIFICATION_LISTENER_SERVICE") || t.substringBefore("ScamNotificationListener").substringAfterLast("<service").contains("BIND_NOTIFICATION_LISTENER_SERVICE"))
    }

    // ---------- Notification mapper ----------
    private fun map(m: NotificationMapper, pkg: String = "com.whatsapp", text: String, ts: Long = 0, ongoing: Boolean = false, group: Boolean = false) = m.map(pkg, text, ongoing, group, ts)

    @Test fun `QA_notifMapper_minLengthBoundary15AfterTrim`() {
        val m = NotificationMapper()
        assertNull(map(m, text = "a".repeat(14)))
        assertNotNull(map(m, text = "   " + "b".repeat(15) + "   "))
        assertNull(map(m, text = "     " + "c".repeat(14) + "     "))
    }

    @Test fun `QA_notifMapper_emptyBlankAndHindiShort`() {
        val m = NotificationMapper()
        assertNull(map(m, text = "")); assertNull(map(m, text = " \n\t "))
        assertNotNull(map(m, text = "आपका खाता बंद हो जाएगा"))
        assertEquals("आपका खाता बंद हो जाएगा".trim(), map(NotificationMapper(), text = "  आपका खाता बंद हो जाएगा ")!!.text)
    }

    @Test fun `QA_notifMapper_dedupeWindowEdges`() {
        val m = NotificationMapper(); val t = "your account will be blocked today"
        assertNotNull(map(m, text = t, ts = 0))
        assertNull(map(m, text = t.uppercase(), ts = 59_999))
        assertNotNull("exactly 60s later is a new alert", map(m, text = t, ts = 60_000))
    }

    @Test fun `QA_notifMapper_ignoredNotificationsDoNotPoisonDedupe`() {
        val m = NotificationMapper(); val t = "your account will be blocked today"
        assertNull(map(m, text = t, ongoing = true)); assertNull(map(m, text = t, group = true)); assertNull(map(m, NotificationMapper.OWN_PACKAGE, t))
        assertNotNull(map(m, text = t))
    }

    @Test fun `QA_notifMapper_packageToSourceTable`() {
        assertEquals(Source.WHATSAPP, NotificationMapper.sourceFor("com.whatsapp.w4b"))
        assertEquals(Source.SMS, NotificationMapper.sourceFor("com.samsung.android.messaging"))
        assertEquals(Source.SMS, NotificationMapper.sourceFor("com.google.android.apps.messaging"))
        assertEquals(Source.NOTIFICATION, NotificationMapper.sourceFor("org.telegram.messenger"))
        assertEquals(Source.NOTIFICATION, NotificationMapper.sourceFor(""))
        assertEquals("lookalike package must not map to WhatsApp", Source.NOTIFICATION, NotificationMapper.sourceFor("com.whatsapp.evil"))
    }

    // ---------- ListenerWiring ----------
    @Test fun `QA_wiring_dispatchUsesMappedSourceNotVerdictSource`() = runBlocking {
        val got = mutableListOf<Source>()
        val w = ListenerWiring(NotificationMapper(), { t, _ -> qaVerdict(Label.SCAM, 0.9, t, Source.CAPTION) }, { _, s -> got += s })
        w.onPosted(NotificationInfo("com.whatsapp", "t", "your account will be blocked today", false, false, 0))
        assertEquals(listOf(Source.WHATSAPP), got)
    }

    @Test fun `QA_wiring_classifyFailurePropagatesAndNeverDispatches`() {
        var dispatched = 0
        val w = ListenerWiring(NotificationMapper(), { _, _ -> error("boom") }, { _, _ -> dispatched++ })
        try { runBlocking { w.onPosted(NotificationInfo("com.whatsapp", "t", "your account will be blocked today", false, false, 0)) }; fail("expected throw") }
        catch (e: IllegalStateException) { /* service wraps with safe{} */ }
        assertEquals(0, dispatched)
    }

    @Test fun `QA_wiring_titleIsNeverClassified`() = runBlocking {
        val seen = mutableListOf<String>()
        val w = ListenerWiring(NotificationMapper(), { t, _ -> seen += t; qaVerdict(Label.SAFE, 0.9, t) }, { _, _ -> })
        w.onPosted(NotificationInfo("com.whatsapp", "SENDER-TITLE-XYZ", "plain body text over fifteen", false, false, 0))
        assertEquals(listOf("plain body text over fifteen"), seen)
    }

    // ---------- Verdict log / privacy ----------
    @Test fun `QA_log_eventTypeHasNoRawTextField`() {
        val names = VerdictEvent::class.java.declaredFields.map { it.name }.toSet()
        assertEquals(setOf("id", "tsMs", "source", "label", "confidence", "scamType", "triggers", "engine"), names)
    }

    @Test fun `QA_log_rowAndChannelMapsHaveExactKeys`() {
        val e = qaEvent()
        assertEquals(setOf("ts_ms", "source", "label", "confidence", "scam_type", "triggers", "engine"), VerdictRowMapper.toRow(e).keys)
        assertEquals(setOf("id", "tsMs", "source", "label", "confidence", "scamType", "triggers", "engine"), VerdictRowMapper.toChannelMap(e).keys)
    }

    @Test fun `QA_log_triggersRoundTripNastyStrings`() {
        val t = listOf("a\"b", "back\\slash", "line\nbreak", "tab\t", "\u0001ctl", "ओटीपी बताइए", "😀", "[\"x\",\"y\"]", ",", "")
        assertEquals(t, VerdictRowMapper.decodeTriggers(VerdictRowMapper.encodeTriggers(t)))
        assertEquals("[]", VerdictRowMapper.encodeTriggers(emptyList()))
    }

    @Test fun `QA_log_decodeTriggersNeverThrowsOnGarbage`() {
        for (s in listOf(null, "", "not json", "[\"abc", "[\"a\\", "[\"\\u00", "[\"\\uZZZZ\"]", "\"", "\\\\\\")) VerdictRowMapper.decodeTriggers(s)
        assertEquals(listOf("a", "b"), VerdictRowMapper.decodeTriggers("[\"a\",\"b\""))
        assertTrue(VerdictRowMapper.decodeTriggers("[\"abc").isEmpty())
    }

    @Test fun `QA_log_fromRowRejectsUnusableAndDefaultsTheRest`() {
        val base = VerdictRowMapper.toRow(qaEvent())
        assertNull(VerdictRowMapper.fromRow(base + ("label" to "BANANA")))
        assertNull(VerdictRowMapper.fromRow(base + ("label" to null)))
        assertNull(VerdictRowMapper.fromRow(base - "ts_ms"))
        val e = VerdictRowMapper.fromRow(mapOf("ts_ms" to 5, "label" to "negative"))!!
        assertEquals(Label.SCAM, e.label); assertEquals(5L, e.tsMs); assertEquals(0.0, e.confidence, 0.0)
        assertTrue(e.triggers.isEmpty()); assertEquals("", e.engine); assertNull(e.scamType)
    }

    @Test fun `QA_log_inMemorySinceIsInclusiveAndSorted`() {
        val l = InMemoryVerdictLog()
        l.append(qaEvent(1, 300)); l.append(qaEvent(2, 100)); l.append(qaEvent(3, 200))
        assertEquals(listOf(200L, 300L), l.since(200).map { it.tsMs })
        assertEquals(listOf(100L, 200L, 300L), l.since(Long.MIN_VALUE).map { it.tsMs })
        assertTrue(l.since(301).isEmpty())
    }

    @Test fun `QA_log_emptyLogHasNoLatestAndNoCounts`() {
        val l = InMemoryVerdictLog(); assertNull(l.latest()); assertTrue(l.countsByType().isEmpty())
    }

    @Test fun `QA_log_countsIgnoreNullTypes`() {
        val l = InMemoryVerdictLog()
        l.append(qaEvent(1, 1, type = ScamType.OTP)); l.append(qaEvent(2, 2, type = ScamType.OTP)); l.append(qaEvent(3, 3, type = null))
        assertEquals(mapOf(ScamType.OTP to 2), l.countsByType())
    }

    // ---------- Trend export ----------
    @Test fun `QA_trend_rowTypeHasExactlyThreeFields`() {
        assertEquals(setOf("district", "scamType", "date"), TrendRow::class.java.declaredFields.map { it.name }.toSet())
    }

    @Test fun `QA_trend_istMidnightBoundary`() {
        val midnightIst = 1_767_637_800_000L // 2026-01-05T18:30:00Z == 2026-01-06 00:00 IST
        val r = TrendExport.rows(listOf(qaEvent(1, midnightIst - 1), qaEvent(2, midnightIst)), "Raipur")
        assertEquals(listOf("2026-01-05", "2026-01-06"), r.map { it.date })
        assertEquals("1970-01-01", TrendExport.rows(listOf(qaEvent(1, 0)), "d")[0].date)
    }

    @Test fun `QA_trend_jsonIsValidAndEscapesDistrict`() {
        val j = TrendExport.export(listOf(qaEvent(1, 0)), "Ra\"ip\\ur\n")
        QAJson.assertValid(j); assertFalse(j.contains("triggers")); assertFalse(j.contains("otp"))
    }

    @Test fun `QA_trend_suspiciousWithTypeIncludedSafeAndUntypedExcluded`() {
        val ev = listOf(qaEvent(1, 0, Label.SUSPICIOUS, ScamType.JOB), qaEvent(2, 0, Label.SAFE, ScamType.JOB), qaEvent(3, 0, Label.SCAM, null))
        assertEquals(listOf(ScamType.JOB), TrendExport.rows(ev, "d").map { it.scamType })
    }
}
