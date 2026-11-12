// Fireplace's notifications, in every Flutter engine: the app's, and the one
// firebase_messaging starts for the background push handler, where the app's
// MainActivity channel does not exist (app decision 0030). Our own code; no
// notification library, as Signal-Android posts its own.
package com.fireplacechat.fireplace_native

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FireplaceNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val app = binding.applicationContext
        context = app
        ensureChannels(app)
        channel = MethodChannel(binding.binaryMessenger, "fireplace/native_notifications").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val app = context ?: return result.error("detached", null, null)
        val manager = app.getSystemService(NotificationManager::class.java)
            ?: return result.error("unavailable", null, null)
        when (call.method) {
            "show" -> {
                show(app, manager, call)
                result.success(null)
            }
            "remove" -> {
                manager.cancel(call.argument<String>("tag"), ID)
                result.success(null)
            }
            "showing" -> result.success(showing(app, manager))
            else -> result.notImplemented()
        }
    }

    private fun show(app: Context, manager: NotificationManager, call: MethodCall) {
        if (!manager.areNotificationsEnabled()) return
        val tag = call.argument<String>("tag") ?: return
        val title = call.argument<String>("title") ?: return
        val body = call.argument<String>("body") ?: return
        val messageId = call.argument<String>("messageId") ?: ""
        // An edit, or an alert on a tag that alerted in the last 20 seconds
        // (from either isolate): update what shows without a new sound.
        val recent = manager.activeNotifications.any {
            it.tag == tag && it.id == ID &&
                System.currentTimeMillis() - it.postTime < QUIET_MS
        }
        val silent = (call.argument<Boolean>("silent") ?: false) || recent
        val channelId = when (call.argument<String>("channel")) {
            SILENT_CHANNEL -> SILENT_CHANNEL
            else -> MESSAGES_CHANNEL
        }
        ensureChannels(app)
        val icon = app.resources.getIdentifier("ic_notification", "drawable", app.packageName)
            .takeIf { it != 0 } ?: app.applicationInfo.icon
        val colorId = app.resources.getIdentifier("notification_color", "color", app.packageName)
        // What a locked screen shows when the person hides sensitive content:
        // today's alert, never the text.
        val public = Notification.Builder(app, channelId)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(PLAIN_BODY)
            .build()
        val builder = Notification.Builder(app, channelId)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .setAutoCancel(true)
            .setOnlyAlertOnce(silent)
            .setGroup(tag)
            .setContentIntent(openApp(app))
            .setExtras(android.os.Bundle().apply { putString(MESSAGE_ID, messageId) })
        if (colorId != 0) builder.setColor(app.getColor(colorId))
        manager.notify(tag, ID, builder.build())
    }

    // Tag -> the message id each Fireplace alert still on screen shows.
    private fun showing(app: Context, manager: NotificationManager): Map<String, String> =
        manager.activeNotifications
            .filter { it.packageName == app.packageName && it.tag != null && it.id == ID }
            .associate { it.tag to (it.notification.extras.getString(MESSAGE_ID) ?: "") }

    private fun openApp(app: Context): PendingIntent? {
        val launch = app.packageManager.getLaunchIntentForPackage(app.packageName) ?: return null
        return PendingIntent.getActivity(app, 0, launch, PendingIntent.FLAG_IMMUTABLE)
    }

    companion object {
        // The ids are also named in the push sender (backend decision 0013) and the
        // app's manifest. FCM's own alerts use id 0 with the same tags, so ours
        // replace them.
        const val MESSAGES_CHANNEL = "messages"
        const val SILENT_CHANNEL = "messages_silent"
        private const val ID = 0
        private const val MESSAGE_ID = "fireplace.messageId"
        private const val PLAIN_BODY = "New Message"
        private const val QUIET_MS = 20_000L

        // A channel's sound cannot change after it is created, so there are two:
        // the sender picks "messages" (the pop) or "messages_silent" per device,
        // following Settings → Notifications → Notification sound. Creating an
        // existing channel only updates its name and description.
        @JvmStatic
        fun ensureChannels(app: Context) {
            val manager = app.getSystemService(NotificationManager::class.java) ?: return
            val alert = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val popId = app.resources.getIdentifier("notification_pop", "raw", app.packageName)
            val pop = if (popId == 0) null else Uri.Builder()
                .scheme(ContentResolver.SCHEME_ANDROID_RESOURCE)
                .authority(app.packageName)
                .appendPath("raw")
                .appendPath(app.resources.getResourceEntryName(popId))
                .build()
            manager.createNotificationChannel(
                NotificationChannel(
                    MESSAGES_CHANNEL,
                    "Messages",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "New messages."
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
    }
}
