package com.hackasol.scamshield

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Opens the system share sheet with plain text. No permission needed; the user picks the recipient. */
object ShareTextChannel {
    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, "scamshield/share").setMethodCallHandler { call, result ->
            val text = call.argument<String>("text")
            if (call.method != "share.text") result.notImplemented()
            else if (text.isNullOrBlank()) result.error("NO_TEXT", "text required", null)
            else try {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            } catch (t: Throwable) { result.error("SHARE", t.message, null) }
        }
    }
}
