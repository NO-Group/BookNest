package com.nogroup.booknest

import android.content.Intent
import android.media.MediaScannerConnection
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter plus the small "booknest/push" channel: Firebase status,
 * the device token, and the screen a tapped notification should open.
 */
class MainActivity : FlutterActivity() {
    companion object {
        /** True while BookNest is on screen — push banners then stay quiet. */
        @Volatile
        var inForeground = false
    }

    private var pushChannel: MethodChannel? = null
    private var pendingRoute: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingRoute = intent?.getStringExtra(BookNestMessagingService.EXTRA_ROUTE)
        // BookNest's own media folder (Android/media/<package>), WhatsApp-
        // style: no storage permission, visible in file managers, photos and
        // videos indexed by the Gallery.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "booknest/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "mediaDir" -> result.success(mediaDir())
                    "scan" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            try {
                                MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                            } catch (e: Throwable) {
                            }
                        }
                        result.success(path != null)
                    }
                    else -> result.notImplemented()
                }
            }
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "booknest/push")
        pushChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(firebaseReady())
                "token" -> {
                    if (!firebaseReady()) {
                        result.success(null)
                    } else {
                        try {
                            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                                result.success(if (task.isSuccessful) task.result else null)
                            }
                        } catch (e: Throwable) {
                            result.success(null)
                        }
                    }
                }
                "deleteToken" -> {
                    if (!firebaseReady()) {
                        result.success(false)
                    } else {
                        try {
                            FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener { task ->
                                result.success(task.isSuccessful)
                            }
                        } catch (e: Throwable) {
                            result.success(false)
                        }
                    }
                }
                "initialRoute" -> {
                    result.success(pendingRoute)
                    pendingRoute = null
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun mediaDir(): String? = try {
        externalMediaDirs.firstOrNull { it != null }?.let { dir ->
            if (!dir.exists()) dir.mkdirs()
            dir.absolutePath
        }
    } catch (e: Throwable) {
        null
    }

    private fun firebaseReady(): Boolean = try {
        FirebaseApp.getApps(this).isNotEmpty()
    } catch (e: Throwable) {
        false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = intent.getStringExtra(BookNestMessagingService.EXTRA_ROUTE) ?: return
        pushChannel?.invokeMethod("open", route)
    }

    override fun onResume() {
        super.onResume()
        inForeground = true
    }

    override fun onPause() {
        inForeground = false
        super.onPause()
    }
}
