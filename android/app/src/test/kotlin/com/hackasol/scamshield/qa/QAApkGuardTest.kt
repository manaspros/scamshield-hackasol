package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class QAApkGuardTest {
    private fun perm(vararg n: String) = n.map { "android.permission.$it" }
    private val devanagari = Regex("[\\u0900-\\u097F]")
    private fun guardSrc() = File(QAPaths.appDir, "src/main/kotlin/com/hackasol/scamshield/ApkGuard.kt").readText()

    // ---------- apk name detection (chat notifications) ----------
    @Test fun `QA_apk_uppercaseExtensionAndMixedCaseDetected`() {
        assertEquals("SBI_REWARDS.APK", ApkRisk.apkNameIn("Rahul", "SBI_REWARDS.APK"))
        assertEquals("bank.Apk", ApkRisk.apkNameIn("bank.Apk", ""))
    }

    @Test fun `QA_apk_nameWithDevanagariAndEmojiDetected`() {
        assertEquals("बैंक_रिवॉर्ड.apk", ApkRisk.apkNameIn("", "📎 बैंक_रिवॉर्ड.apk"))
    }

    @Test fun `QA_apk_doubleExtensionApkPdfIsStillFlagged`() {
        assertNotNull(ApkRisk.apkNameIn("", "invoice.apk.pdf"))
    }

    @Test fun `QA_apk_benignFilesAndLookalikesAreNotFlagged`() {
        for (t in listOf("report.pdf", "photo.jpg", "notes.apks.txt", "see you at the apk store", "apk", "file.apkx", "my.apkg", "", "   ", "dinner.apk-free menu".substringBefore("-").replace(".apk", ".ap")))
            assertNull("'$t'", ApkRisk.apkNameIn(t, t))
    }

    @Test fun `QA_apk_titleIsCheckedBeforeText`() {
        assertEquals("a.apk", ApkRisk.apkNameIn("a.apk", "b.apk"))
        assertEquals("b.apk", ApkRisk.apkNameIn("hello", "b.apk"))
    }

    @Test fun `QA_apk_nameStopsAtWhitespaceAndQuotes`() {
        assertEquals("pack.apk", ApkRisk.apkNameIn("", "download \"pack.apk\" now"))
        assertEquals("setup.apk", ApkRisk.apkNameIn("", "http://x.example/dl/setup.apk"))
    }

    @Test fun `QA_apk_noArgsIsNull`() { assertNull(ApkRisk.apkNameIn()) }

    @Test(timeout = 20_000) fun `QA_apk_veryLongTextWithApkAtEndIsFound`() {
        assertNotNull(ApkRisk.apkNameIn("t", "word ".repeat(50_000) + "x.apk"))
    }

    // ---------- permission scoring ----------
    @Test fun `QA_apk_emptyPermissionListIsLowZero`() {
        val r = ApkRisk.assess(emptyList(), fromUnknownSource = true); assertEquals(ApkRiskLevel.LOW, r.level); assertEquals(0, r.score)
    }

    @Test fun `QA_apk_mediumBoundaryAt25`() {
        assertEquals(ApkRiskLevel.MEDIUM, ApkRisk.assess(perm("READ_CONTACTS", "CALL_PHONE")).level)         // 15+10
        assertEquals(ApkRiskLevel.LOW, ApkRisk.assess(perm("CALL_PHONE", "QUERY_ALL_PACKAGES")).level)       // 20
        assertEquals(ApkRiskLevel.MEDIUM, ApkRisk.assess(perm("CALL_PHONE", "QUERY_ALL_PACKAGES"), true).level) // 20 + 10 bonus
    }

    @Test fun `QA_apk_highBoundaryAt60`() {
        assertEquals(ApkRiskLevel.HIGH, ApkRisk.assess(perm("BIND_NOTIFICATION_LISTENER_SERVICE", "SEND_SMS")).level)      // 35+25
        assertEquals(ApkRiskLevel.MEDIUM, ApkRisk.assess(perm("BIND_ACCESSIBILITY_SERVICE", "READ_CONTACTS")).level)        // 55
        assertEquals(ApkRiskLevel.HIGH, ApkRisk.assess(perm("BIND_ACCESSIBILITY_SERVICE", "READ_CONTACTS"), true).level)    // 65
    }

    @Test fun `QA_apk_unknownSourceBonusOnlyWhenSomethingRisky`() {
        assertEquals(0, ApkRisk.assess(perm("INTERNET"), true).score)
        assertEquals(ApkRisk.assess(perm("SEND_SMS")).score + ApkRisk.UNKNOWN_SOURCE_BONUS, ApkRisk.assess(perm("SEND_SMS"), true).score)
    }

    @Test fun `QA_apk_otpStealerComboIsHighEvenWithReceiveSmsAndNoOtherRisk`() {
        val r = ApkRisk.assess(perm("RECEIVE_SMS", "INTERNET", "READ_CONTACTS")); assertEquals(ApkRiskLevel.HIGH, r.level); assertTrue(r.score >= ApkRisk.COMBO_SCORE)
        assertNotEquals(ApkRiskLevel.HIGH, ApkRisk.assess(perm("INTERNET", "READ_CONTACTS")).level)
        assertEquals(ApkRiskLevel.MEDIUM, ApkRisk.assess(perm("READ_SMS", "INTERNET")).level)
    }

    @Test fun `QA_apk_scoreCappedAt100AndDuplicatesCountOnce`() {
        val all = ApkRisk.assess(perm("RECEIVE_SMS", "READ_SMS", "SEND_SMS", "BIND_ACCESSIBILITY_SERVICE", "SYSTEM_ALERT_WINDOW", "REQUEST_INSTALL_PACKAGES",
            "BIND_NOTIFICATION_LISTENER_SERVICE", "READ_CONTACTS", "READ_CALL_LOG", "CALL_PHONE", "BIND_DEVICE_ADMIN", "QUERY_ALL_PACKAGES"), true)
        assertEquals(100, all.score); assertEquals(ApkRiskLevel.HIGH, all.level); assertEquals(12, all.risky.size)
        assertEquals(ApkRisk.assess(perm("SEND_SMS")).score, ApkRisk.assess(perm("SEND_SMS", "SEND_SMS", "SEND_SMS")).score)
    }

    @Test fun `QA_apk_everyRiskyEntryIsHindiAndEnglish`() {
        val all = ApkRisk.assess(perm("RECEIVE_SMS", "READ_SMS", "SEND_SMS", "BIND_ACCESSIBILITY_SERVICE", "SYSTEM_ALERT_WINDOW", "REQUEST_INSTALL_PACKAGES",
            "BIND_NOTIFICATION_LISTENER_SERVICE", "READ_CONTACTS", "READ_CALL_LOG", "CALL_PHONE", "BIND_DEVICE_ADMIN", "QUERY_ALL_PACKAGES"))
        for (x in all.risky) { assertTrue(x.permission, devanagari.containsMatchIn(x.hindiReason)); assertTrue(x.permission, x.englishReason.isNotBlank() && !devanagari.containsMatchIn(x.englishReason)) }
    }

    @Test fun `QA_apk_unknownAndNormalPermissionsAreIgnoredAndBarePermissionNamesWork`() {
        assertEquals(0, ApkRisk.assess(perm("VIBRATE", "WAKE_LOCK", "ACCESS_NETWORK_STATE", "WRITE_SECURE_SETTINGS")).score)
        assertEquals(ApkRiskLevel.MEDIUM, ApkRisk.assess(listOf("SEND_SMS")).level)
        assertEquals(0, ApkRisk.assess(perm("read_sms")).score)
    }

    @Test fun `QA_apk_resultCarriesPermissionNamesOnlyNoLabelOrPackage`() {
        val r = ApkRisk.assess(perm("SEND_SMS"), true, label = "SECRET-LABEL-XYZ", packageName = "com.secret.pkg")
        assertFalse(r.toString().contains("SECRET-LABEL")); assertFalse(r.toString().contains("com.secret.pkg"))
    }

    // ---------- warning text + privacy (source-level; ApkGuard needs Android classes) ----------
    @Test fun `QA_apk_warningTitlesAreHindiFirst`() {
        val src = guardSrc()
        for (title in Regex("\"([^\"]*(?:इंस्टॉल न करें|Do not install)[^\"]*)\"").findAll(src).map { it.groupValues[1] }.toList()) {
            val firstHi = devanagari.find(title)?.range?.first ?: Int.MAX_VALUE
            val firstEn = Regex("[A-Za-z]").find(title)?.range?.first ?: Int.MAX_VALUE
            assertTrue("English before Hindi in '$title'", firstHi < firstEn)
        }
        assertTrue(src.contains("इस ऐप को इंस्टॉल न करें / Do not install"))
        assertTrue(src.contains("इंस्टॉल न करें / Do not install"))
    }

    @Test fun `QA_apk_guardNeverLogsAndNeverSendsFileContentAnywhere`() {
        val src = guardSrc()
        for (bad in listOf("Log.", "println", "readBytes", "readText", "HttpURLConnection", "OkHttp", "URL(", "Socket", "sendBroadcast")) assertFalse("ApkGuard uses $bad", src.contains(bad))
    }

    @Test fun `QA_apk_guardNeverInstallsTheFile`() {
        val src = guardSrc()
        for (bad in listOf("ACTION_VIEW", "ACTION_INSTALL_PACKAGE", "PackageInstaller", "application/vnd.android.package-archive")) assertFalse("ApkGuard uses $bad", src.contains(bad))
    }

    @Test fun `QA_apk_contentCopyIsDeletedButCallersFileIsNot`() {
        val src = guardSrc()
        assertTrue(src.contains("finally")); assertTrue(src.contains("scheme != \"file\"")); assertTrue(src.contains(".delete()"))
    }

    @Test fun `QA_apk_notificationPostedWithDistinctIdAndReportRoute`() {
        val src = guardSrc(); assertTrue(src.contains("NOTIF_ID = 7002")); assertTrue(src.contains("\"route\", \"report\""))
    }

    // ---------- share path ----------
    @Test fun `QA_apk_shareIntentMapperNeverTreatsApkMimeAsText`() {
        assertNull(ShareIntentMapper.map("android.intent.action.SEND", "application/vnd.android.package-archive", "text"))
        assertNull(ShareIntentMapper.map("android.intent.action.SEND", "application/octet-stream", "text"))
        assertNull(ShareIntentMapper.map("android.intent.action.SEND", null, "text"))
    }

    @Test fun `QA_apk_shareIntentMapperTextEdges`() {
        assertEquals("x", ShareIntentMapper.map("android.intent.action.SEND", " TEXT/PLAIN; charset=utf-8 ", "  x  "))
        assertNull(ShareIntentMapper.map("android.intent.action.SEND", "text/plain", "   ")); assertNull(ShareIntentMapper.map("android.intent.action.SEND", "text/plain", null))
        assertNull(ShareIntentMapper.map("android.intent.action.VIEW", "text/plain", "x")); assertNull(ShareIntentMapper.map(null, "text/plain", "x"))
        assertEquals(ShareIntentMapper.MAX_CHARS, ShareIntentMapper.map("android.intent.action.SEND", "text/plain", "क".repeat(5000))!!.length)
    }

    @Test fun `QA_apk_textShareMentioningApkIsStillScoredByRules`() {
        assertNotEquals(Label.SAFE, RuleScorer.score("download SBI_Rewards.apk and install, link par click karo").label)
    }
}
