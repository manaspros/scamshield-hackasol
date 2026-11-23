package com.hackasol.scamshield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.ApkRisk
import com.hackasol.scamshield.core.ApkRiskLevel
import com.hackasol.scamshield.core.ApkRiskResult
import java.io.File

/** Reads an .apk's requested permissions (never installs it) and posts a heads-up warning. Blocking: call off the main thread. */
object ApkGuard {
    private const val CHANNEL_ID = AlertNotificationMapper.CHANNEL_ID_ALERTS   // same channel as AlertDispatcher
    private const val NOTIF_ID = 7002              // distinct from the dispatcher's 7001 so neither replaces the other

    /** [uri] is a content:// or file:// Uri (or a bare path) of an .apk. Null if it cannot be parsed. */
    fun check(ctx: Context, uri: Uri): ApkRiskResult? {
        val path = toLocalPath(ctx, uri) ?: return null
        try {
            val pm = ctx.packageManager
            val info = if (Build.VERSION.SDK_INT >= 33)
                pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
            else @Suppress("DEPRECATION") pm.getPackageArchiveInfo(path, PackageManager.GET_PERMISSIONS)
            return info?.let {
                val r = ApkRisk.assess(it.requestedPermissions?.toList().orEmpty(), fromUnknownSource = true, packageName = it.packageName)
                if (r.level != ApkRiskLevel.LOW) warn(ctx, it.packageName, r)
                r
            }
        } finally {
            // Only the cache copy made from a content:// stream; never delete the caller's own file:// path.
            if (uri.scheme != null && uri.scheme != "file") File(path).delete()
        }
    }

    /** Notification text only mentioned an .apk (no file access from a notification), so no permission scoring. */
    fun warnChatApk(ctx: Context, fileName: String) = post(ctx,
        "इंस्टॉल न करें / Do not install",
        "चैट में भेजे गए ऐप्स (.apk) इंस्टॉल न करें: $fileName\nDon't install apps sent in chats: $fileName")

    // PackageManager needs a file path, so content:// streams are copied into cache first.
    private fun toLocalPath(ctx: Context, uri: Uri): String? {
        if (uri.scheme == null || uri.scheme == "file") return uri.path
        val out = File(ctx.cacheDir, "apkguard.apk")
        ctx.contentResolver.openInputStream(uri)?.use { i -> out.outputStream().use { i.copyTo(it) } } ?: return null
        return out.path
    }

    private fun warn(ctx: Context, appName: String, r: ApkRiskResult) = post(ctx,
        "इस ऐप को इंस्टॉल न करें / Do not install: $appName",
        "Risk ${r.level} (${r.score}/100)\n" + r.risky.joinToString("\n") { "• ${it.hindiReason} / ${it.englishReason}" })

    private fun post(ctx: Context, title: String, text: String) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "स्कैम अलर्ट / Scam alerts", NotificationManager.IMPORTANCE_HIGH))
        val report = PendingIntent.getActivity(ctx, "report".hashCode(),
            Intent(ctx, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra("route", "report"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        nm.notify(NOTIF_ID, Notification.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_shield)
            .setContentTitle(title)
            .setContentText(text.substringBefore('\n'))
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setCategory(Notification.CATEGORY_ALARM)
            .setContentIntent(report)
            .addAction(Notification.Action.Builder(null, "Report", report).build())
            .setAutoCancel(true).build())
    }
}
