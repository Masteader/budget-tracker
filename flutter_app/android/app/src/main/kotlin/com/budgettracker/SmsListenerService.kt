package com.budgettracker

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * SmsListenerService
 *
 * A foreground Service that keeps the app alive in the background so the
 * SmsBroadcastReceiver can forward intercepted SMS messages to Flutter via
 * a MethodChannel. This satisfies Android 12+ foreground service requirements.
 *
 * MethodChannel:  "com.budgettracker/sms"
 * Method name:    "onSmsReceived"
 * Arguments:      Map { "body": String, "sender": String, "timestamp": Long }
 */
class SmsListenerService : Service() {

    companion object {
        private const val TAG = "SmsListenerService"
        private const val CHANNEL_ID = "budget_tracker_sms_channel"
        private const val NOTIFICATION_ID = 1001
        const val METHOD_CHANNEL = "com.budgettracker/sms"

        /** Called by SmsBroadcastReceiver when a bank SMS arrives. */
        fun forwardSmsToFlutter(context: Context, body: String, sender: String, timestamp: Long) {
            val engine: FlutterEngine = FlutterEngineCache.getInstance()
                .get("main_engine") ?: run {
                Log.w(TAG, "Flutter engine not cached — SMS will be queued locally.")
                // The FlutterActivity will drain the SQLite queue on next resume.
                SmsQueue.enqueue(context, body, sender, timestamp)
                return
            }

            engine.dartExecutor.binaryMessenger.let { messenger ->
                val channel = MethodChannel(messenger, METHOD_CHANNEL)
                channel.invokeMethod(
                    "onSmsReceived",
                    mapOf("body" to body, "sender" to sender, "timestamp" to timestamp),
                )
                Log.d(TAG, "SMS forwarded to Flutter: sender=$sender len=${body.length}")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "SmsListenerService created.")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand called.")
        return START_STICKY   // restart automatically if killed by the OS
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "SmsListenerService destroyed — will be restarted.")
        super.onDestroy()
    }

    // ── Notification ────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SMS Budget Monitor",
                NotificationManager.IMPORTANCE_LOW,   // silent
            ).apply {
                description = "Monitors incoming bank SMS messages for budget tracking."
                setShowBadge(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Budget Tracker")
            .setContentText("Monitoring bank SMS messages…")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
