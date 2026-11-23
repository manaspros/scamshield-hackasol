package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ApkRiskTest {
    @Test fun T5_8_smsInternetContactsHigh() {
        val r = ApkRisk.assess(listOf(
            "android.permission.READ_SMS", "android.permission.INTERNET", "android.permission.READ_CONTACTS"))
        assertEquals(ApkRiskLevel.HIGH, r.level)
        assertTrue(r.score >= ApkRisk.COMBO_SCORE)
        assertEquals(setOf("android.permission.READ_SMS", "android.permission.READ_CONTACTS"), r.risky.map { it.permission }.toSet())
        assertTrue(r.risky.all { it.hindiReason.isNotBlank() && it.englishReason.isNotBlank() })
    }

    @Test fun T5_8_plainAppLow() {
        val r = ApkRisk.assess(listOf(
            "android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE", "android.permission.VIBRATE"),
            fromUnknownSource = true)
        assertEquals(ApkRiskLevel.LOW, r.level)
        assertEquals(0, r.score)
        assertTrue(r.risky.isEmpty())
    }

    @Test fun T5_8_apkNameInNotification() {
        assertEquals("SBI_Rewards.apk", ApkRisk.apkNameIn("Rahul", "📎 SBI_Rewards.apk"))
        assertEquals(null, ApkRisk.apkNameIn("Rahul", "see you at 5 apk store"))
    }

    @Test fun T5_8_accessibilityAloneHigh() {
        assertEquals(ApkRiskLevel.HIGH, ApkRisk.assess(listOf("android.permission.BIND_ACCESSIBILITY_SERVICE", "android.permission.BIND_DEVICE_ADMIN")).level)
    }

    @Test fun T5_8_singleModerateMedium() {
        assertEquals(ApkRiskLevel.MEDIUM, ApkRisk.assess(listOf("android.permission.SEND_SMS")).level)
    }
}
