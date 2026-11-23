package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test

/** Regression tests for STT/APK bugs fixed in fddef91. */
class QARegressionSttApkTest {
    @Test fun `QA_stt_deeplyNestedGarbageIsNullNotStackOverflow`() {
        assertNull(SttResultParser.parse("[".repeat(100_000)))
        assertNull(SttResultParser.parse("{\"a\":".repeat(50_000)))
    }

    @Test fun `QA_stt_hugeOrNegativeStartIsClampedToSaneMillis`() {
        val s = SttResultParser.parse("""{"result":[{"start":1e999}],"text":"a b"}""", 5)
        assertTrue("startMs=${s?.startMs}", s == null || s.startMs in 0..86_400_000L)
        val n = SttResultParser.parse("""{"result":[{"start":-3.5}],"text":"a b"}""", 5)
        assertTrue("startMs=${n?.startMs}", n == null || n.startMs >= 0)
    }

    @Test(timeout = 20_000) fun `QA_apk_longSpacelessNotificationDoesNotBlowUpTheListener`() {
        assertNull(ApkRisk.apkNameIn("t", "a".repeat(100_000)))
    }

    // Source-level: ShareReceiver needs Android classes, so the routing is checked in the source and manifest.
    @Test fun `QA_apk_octetStreamShareWithApkNameReachesTheGuard`() {
        val app = java.io.File(QAPaths.appDir, "src/main")
        val manifest = java.io.File(app, "AndroidManifest.xml").readText()
        val share = java.io.File(app, "kotlin/com/hackasol/scamshield/ShareReceiver.kt").readText()
        assertTrue("manifest must offer ScamShield for octet-stream shares", manifest.contains("android:mimeType=\"application/octet-stream\""))
        assertTrue(share.contains("OCTET_MIME") && share.contains("endsWith(\".apk\", ignoreCase = true)"))
        assertTrue("octet-stream accepted only with an .apk name, otherwise finish()", Regex("APK_MIME \\|\\| sharedName\\(\\)\\?\\.endsWith\\(\"\\.apk\", ignoreCase = true\\) == true\\) checkApk\\(\\) else finish\\(\\)").containsMatchIn(share))
    }

    @Test fun `QA_apk_customPermissionWithSameSuffixIsNotTreatedAsSystemPermission`() {
        assertEquals(0, ApkRisk.assess(listOf("com.vendor.permission.READ_SMS")).score)
    }
}
