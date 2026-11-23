package com.hackasol.scamshield

import android.content.Context
import com.hackasol.scamshield.core.InCallSignals
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.PaymentGuard

/**
 * Glue between the foreground/notification detectors and PaymentGuard. Blocking (reads the verdict log): call off the main thread.
 * Risky-verdict time comes from the verdict log (every source goes through TextApi.classify, so no second store to keep in sync).
 */
object ForegroundHook {
    @Volatile private var lastWarnedMs: Long? = null

    // @Synchronized: check-then-set of lastWarnedMs must be atomic (foreground and notification callbacks run on different coroutines).
    @Synchronized
    fun onForeground(ctx: Context, pkg: String, nowMs: Long) {
        if (pkg !in InCallSignals.PAYMENT_APPS) return   // cheap exit before touching SQLite
        val lastRisky = TextApi.verdictLog?.since(nowMs - PaymentGuard.WINDOW_MS)
            ?.filter { it.label != Label.SAFE }?.maxOfOrNull { it.tsMs }
        if (PaymentGuard.shouldWarnOnForeground(pkg, nowMs, lastRisky, lastWarnedMs)) warn(ctx, nowMs)
    }

    @Synchronized
    fun onNotification(ctx: Context, pkg: String, title: String, text: String, nowMs: Long) {
        if (PaymentGuard.shouldWarnOnCollect(pkg, title, text, nowMs, lastWarnedMs)) warn(ctx, nowMs)
    }

    private fun warn(ctx: Context, nowMs: Long) {
        lastWarnedMs = nowMs
        PaymentGuardNotifier.post(ctx)
    }
}
