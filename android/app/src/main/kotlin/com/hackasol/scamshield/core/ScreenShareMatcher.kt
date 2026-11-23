package com.hackasol.scamshield.core

/**
 * Recognises Android's screen-capture consent dialog (MediaProjection) and screen-share / cast notifications.
 * Pure: the service passes the window package + gathered text, or the notification text.
 *
 * The dialog is only matched when it comes from a system package, so a chat that merely says "start sharing" is ignored.
 */
object ScreenShareMatcher {
    /** MediaProjection consent is a SystemUI activity; some builds route it through the permission controller. */
    val DIALOG_PACKAGES = setOf(
        "com.android.systemui",
        "com.google.android.permissioncontroller",
        "com.android.permissioncontroller",
    )

    // English strings are from AOSP SystemUI (media_projection_* resources, Android 11-15).
    // [VERIFY] The Hindi strings were written from the AOSP hi translations by memory and not checked on a device;
    // OEM skins reword the dialog, so treat the list as best effort.
    private val DIALOG_RE = UnicodeRegex.of(
        "start recording or casting|start recording or cast|start casting|start sharing|" +
            "share or record your screen|share your screen|share entire screen|share one app|" +
            "will have access to all of the information that is visible on your screen|" +
            "रिकॉर्डिंग या कास्टिंग शुरू|कास्ट करना शुरू|शेयर करना शुरू|साझा करना शुरू|" +
            "आपकी स्क्रीन पर दिखने वाली सभी जानकारी"
    )

    // Notifications posted while a screen is shared or cast ("You're sharing your screen", "Screen sharing", "Casting screen").
    private val NOTIFICATION_RE = UnicodeRegex.of(
        "sharing your screen|screen sharing|screen is being shared|sharing screen|casting (your )?screen|cast(ing)? screen|screen cast|" +
            "स्क्रीन शेयर|स्क्रीन साझा|स्क्रीन कास्ट"
    )

    fun isDialog(pkg: String, text: String): Boolean = pkg in DIALOG_PACKAGES && DIALOG_RE.containsMatchIn(text)

    /** The matched phrase, or null. */
    fun notificationMatch(text: String): String? = NOTIFICATION_RE.find(text)?.value
}
