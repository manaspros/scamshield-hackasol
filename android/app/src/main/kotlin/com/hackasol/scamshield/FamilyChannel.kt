package com.hackasol.scamshield

import android.content.Context
import com.hackasol.scamshield.core.Totp
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Channel `scamshield/family`: pairing secret storage + TOTP code. The code maths lives only in core/Totp.kt. */
object FamilyChannel {
    private const val PREFS = "scamshield_family"
    private const val KEY = "secret"
    private const val STEP_MS = 30_000L
    private val BASE32 = Regex("[A-Z2-7]{16,}")

    /** Strip spaces/dashes, upper-case; null if not a base32 secret of at least 80 bits. */
    internal fun normalize(raw: String?): String? =
        raw?.filterNot { it == ' ' || it == '-' }?.uppercase()?.takeIf { BASE32.matches(it) }

    fun register(messenger: BinaryMessenger, context: Context) {
        // shortcut: secret in plain SharedPreferences, upgrade to EncryptedSharedPreferences/Keystore before release
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        MethodChannel(messenger, "scamshield/family").setMethodCallHandler { call, result ->
            when (call.method) {
                "family.status" -> result.success(mapOf("paired" to (prefs.getString(KEY, null) != null)))
                "family.newSecret" -> {
                    val s = Totp.generateSecret(20) // 160 bits
                    prefs.edit().putString(KEY, s).apply()
                    result.success(s)
                }
                "family.setSecret" -> {
                    val s = normalize(call.argument<String>("secret"))
                    if (s == null) result.error("BAD_SECRET", "not a base32 secret", null)
                    else { prefs.edit().putString(KEY, s).apply(); result.success(null) }
                }
                "family.code" -> {
                    val s = prefs.getString(KEY, null)
                    if (s == null) result.error("NOT_PAIRED", "no secret", null)
                    else {
                        val now = System.currentTimeMillis()
                        result.success(mapOf(
                            "code" to Totp.code(s, now),
                            "remainingSec" to ((STEP_MS - now % STEP_MS + 999) / 1000).toInt(),
                        ))
                    }
                }
                "family.unpair" -> { prefs.edit().remove(KEY).apply(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
