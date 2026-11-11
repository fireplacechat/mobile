package com.fireplacechat.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessagesChannel()
    }

    // `fireplace/notifications`; see lib/src/model/notifications/system_notifications.dart.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fireplace/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Android has no numeric icon badge API; launchers show a dot
                    // while a notification from the Messages channel is in the shade.
                    "setBadge" -> result.success(null)
                    "clearDelivered" -> {
                        getSystemService(NotificationManager::class.java)?.cancelAll()
                        result.success(null)
                    }
                    "openSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The channel pushes arrive on (named in the sender and the manifest). It
    // appears as "Messages" in the system settings, where people can change its
    // sound and importance.
    private fun createMessagesChannel() {
        val channel = NotificationChannel(
            MESSAGES_CHANNEL,
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New messages. Shows who wrote, never what they wrote."
            setShowBadge(true)
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    private companion object {
        const val MESSAGES_CHANNEL = "messages"
    }
}
