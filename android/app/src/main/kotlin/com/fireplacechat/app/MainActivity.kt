package com.fireplacechat.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sounds: SoundPool? = null
    private var sendSound = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessageChannels()
    }

    override fun onDestroy() {
        sounds?.release()
        sounds = null
        super.onDestroy()
    }

    // `fireplace/notifications`; see lib/src/model/notifications/system_notifications.dart.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        loadSendSound()
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
                    "playSendSound" -> {
                        playSendSound()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun loadSendSound() {
        if (sounds != null) return
        val pool = SoundPool.Builder()
            .setMaxStreams(2)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
        sendSound = pool.load(this, R.raw.send_pop, 1)
        sounds = pool
    }

    // Like a keyboard click: only when the phone is not on silent or vibrate.
    private fun playSendSound() {
        val audio = getSystemService(AudioManager::class.java) ?: return
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        sounds?.play(sendSound, 0.8f, 0.8f, 1, 0, 1f)
    }

    // A channel's sound cannot change after it is created, so there are two:
    // the sender picks "messages" (the pop) or "messages_silent" per device,
    // following Settings → Notifications → Notification sound. The ids are
    // also named in the push sender and the manifest.
    private fun createMessageChannels() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val pop = Uri.Builder()
            .scheme(ContentResolver.SCHEME_ANDROID_RESOURCE)
            .authority(packageName)
            .appendPath("raw")
            .appendPath(resources.getResourceEntryName(R.raw.notification_pop))
            .build()
        val alert = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        manager.createNotificationChannel(
            NotificationChannel(
                MESSAGES_CHANNEL,
                "Messages",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "New messages. Shows who wrote, never what they wrote."
                setSound(pop, alert)
                setShowBadge(true)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                SILENT_CHANNEL,
                "Messages without sound",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "New messages, when Notification sound is off in Fireplace."
                setSound(null, null)
                setShowBadge(true)
            },
        )
    }

    private companion object {
        const val MESSAGES_CHANNEL = "messages"
        const val SILENT_CHANNEL = "messages_silent"
    }
}
