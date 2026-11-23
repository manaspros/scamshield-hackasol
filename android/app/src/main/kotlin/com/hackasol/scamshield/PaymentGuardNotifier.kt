package com.hackasol.scamshield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.hackasol.scamshield.core.PaymentGuard

/** One calm heads-up with two dial actions. Never full-screen, never an overlay, so it cannot cover the payment app. */
object PaymentGuardNotifier {
    private const val ID = 7002
    private const val TIMEOUT_MS = 2 * 60_000L
    /** Optional, read-only: set by whatever stores a family number later. Nothing in the app writes it today. */
    const val FAMILY_PREFS = "scamshield_family"
    const val FAMILY_PHONE_KEY = "family_phone"
    private val PHONE = Regex("\\+?[0-9]{5,15}")

    fun post(ctx: Context) {
        val c = PaymentGuard.content(AppSettings.lang)
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(PaymentGuard.CHANNEL_ID, c.channel, NotificationManager.IMPORTANCE_DEFAULT))
        fun pi(code: Int, i: Intent) = PendingIntent.getActivity(ctx, code, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val phone = ctx.getSharedPreferences(FAMILY_PREFS, Context.MODE_PRIVATE).getString(FAMILY_PHONE_KEY, null)
            ?.filterNot { it == ' ' || it == '-' }?.takeIf { PHONE.matches(it) }
        val family = if (phone != null) pi(ID + 1, Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", phone, null)))
        else pi(ID + 1, Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("route", PaymentGuard.ROUTE_FAMILY))
        val helpline = pi(ID + 2, Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", PaymentGuard.HELPLINE, null)))
        val b = Notification.Builder(ctx, PaymentGuard.CHANNEL_ID)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(c.title)
            .setContentText(c.text)
            .setStyle(Notification.BigTextStyle().bigText(c.text))
            .setCategory(Notification.CATEGORY_STATUS)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setTimeoutAfter(TIMEOUT_MS)
            .setContentIntent(family)
            .addAction(Notification.Action.Builder(null, c.callFamily, family).build())
            .addAction(Notification.Action.Builder(null, c.call1930, helpline).build())
        nm.notify(ID, b.build())
    }
}
