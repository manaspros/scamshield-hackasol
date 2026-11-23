package com.hackasol.scamshield

import android.app.Activity
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Channel `scamshield/qr`: `qr.scan` -> raw QR value (String), null if the user cancelled,
 * error "UNAVAILABLE" if Google Play services / the scanner module is missing.
 * Play services hosts the camera UI, so the app needs no CAMERA permission. Parsing stays in UpiQr (via upi.check).
 */
object QrChannel {
    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, "scamshield/qr").setMethodCallHandler { call, result ->
            if (call.method != "qr.scan") { result.notImplemented(); return@setMethodCallHandler }
            val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
            // shortcut: any scanner failure is reported as UNAVAILABLE, split cancel-vs-missing-module codes if a device shows otherwise
            GmsBarcodeScanning.getClient(activity, options).startScan()
                .addOnSuccessListener { result.success(it.rawValue) }
                .addOnCanceledListener { result.success(null) }
                .addOnFailureListener { result.error("UNAVAILABLE", it.message, null) }
        }
    }
}
