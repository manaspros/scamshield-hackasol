package com.hackasol.scamshield

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.ShareIntentMapper
import com.hackasol.scamshield.core.Source
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Share-sheet target: "Share > ScamShield" on any text. Transparent; classifies with source=SHARE,
 * raises the normal alert (notification only, no overlay), shows a one-line toast, then closes.
 */
class ShareReceiver : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = ShareIntentMapper.map(intent?.action, intent?.type, intent?.getCharSequenceExtra(EXTRA_TEXT))
        if (text == null) { finish(); return }
        val app = applicationContext
        scope.launch {
            try {
                TextApi.init(app)
                val v = TextApi.classify(ClassifyRequest(text, source = Source.SHARE))
                withContext(Dispatchers.Main) {
                    AlertDispatcher(app, null).dispatch(v, v.label, v.label, v.risk)
                    Toast.makeText(app, "ScamShield ने यह संदेश जाँचा: ${hindi(v.label)}\n" +
                        "ScamShield checked this message: ${v.label.name}", Toast.LENGTH_LONG).show()
                }
            } catch (t: Throwable) {
                Log.e("ScamShield/Share", "classify failed", t)
            } finally {
                withContext(Dispatchers.Main) { finish() }
            }
        }
    }

    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    private fun hindi(l: Label) = when (l) {
        Label.SAFE -> "सामान्य बातचीत"
        Label.SUSPICIOUS -> "सावधान रहें"
        Label.SCAM -> "धोखाधड़ी हो सकती है"
    }

    private companion object { const val EXTRA_TEXT = android.content.Intent.EXTRA_TEXT }
}
