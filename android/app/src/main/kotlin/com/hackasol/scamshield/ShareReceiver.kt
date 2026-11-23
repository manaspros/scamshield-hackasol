package com.hackasol.scamshield

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.L10n
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.ShareIntentMapper
import com.hackasol.scamshield.core.Source
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Share-sheet target: "Share > ScamShield" on any text. Transparent; it closes at once (a translucent activity that stays
 * up during a slow Gemma classify takes every touch and looks frozen) and the check runs in a process-wide scope, so
 * Back cannot cancel it. The result arrives as the normal alert (notification only, no overlay) plus a one-line toast.
 */
class ShareReceiver : Activity() {
    private val scope get() = WORK

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == android.content.Intent.ACTION_SEND && (intent?.type == APK_MIME || intent?.type == OCTET_MIME)) {
            // octet-stream is what many chat apps send for an .apk; only a name ending in .apk is treated as one.
            if (intent?.type == APK_MIME || sharedName()?.endsWith(".apk", ignoreCase = true) == true) checkApk() else finish()
            return
        }
        val text = ShareIntentMapper.map(intent?.action, intent?.type, intent?.getCharSequenceExtra(EXTRA_TEXT))
        if (text == null) { finish(); return }
        val app = applicationContext
        Toast.makeText(app, "ScamShield जाँच रहा है…\nScamShield is checking…", Toast.LENGTH_SHORT).show()
        finish()
        scope.launch {
            try {
                TextApi.init(app)
                val v = TextApi.classify(ClassifyRequest(text, source = Source.SHARE))
                withContext(Dispatchers.Main) {
                    AlertDispatcher(app, null).dispatch(v, v.label, v.label, v.risk)
                    Toast.makeText(app, "ScamShield ने यह संदेश जाँचा: ${hindi(v.label)}\n" +
                        "ScamShield checked this message: ${L10n.labelWord(v.label, "en")}", Toast.LENGTH_LONG).show()
                }
            } catch (t: Throwable) {
                Log.e("ScamShield/Share", "classify failed", t)
            }
        }
    }

    private fun sharedUri(): android.net.Uri? =
        if (android.os.Build.VERSION.SDK_INT >= 33)
            intent.getParcelableExtra(android.content.Intent.EXTRA_STREAM, android.net.Uri::class.java)
        else @Suppress("DEPRECATION") intent.getParcelableExtra<android.net.Uri>(android.content.Intent.EXTRA_STREAM)

    private fun sharedName(): String? {
        val uri = sharedUri() ?: return null
        val shown = try {
            contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (_: Exception) { null }
        return shown ?: uri.lastPathSegment
    }

    private fun checkApk() {
        val uri = sharedUri()
        val app = applicationContext
        // The shared content:// grant lasts while this activity is alive, so the APK is copied/read before finishing.
        scope.launch {
            try {
                if (uri != null) ApkGuard.check(app, uri)
            } catch (t: Throwable) {
                Log.e("ScamShield/Share", "apk check failed", t)
            } finally {
                withContext(Dispatchers.Main) { finish() }
            }
        }
    }

    private fun hindi(l: Label) = when (l) {
        Label.SAFE -> "सामान्य बातचीत"
        Label.SUSPICIOUS -> "सावधान रहें"
        Label.SCAM -> "धोखाधड़ी हो सकती है"
    }

    private companion object {
        /** Outlives the activity on purpose: a shared message is checked even after the user presses Back. */
        val WORK = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        const val EXTRA_TEXT = android.content.Intent.EXTRA_TEXT
        const val APK_MIME = "application/vnd.android.package-archive"
        const val OCTET_MIME = "application/octet-stream"
    }
}
