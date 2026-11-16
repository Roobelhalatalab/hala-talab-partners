package com.halatalab.partners

import android.app.Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/** Merchant-only ring session started from the visible merchant dashboard.
 *  The OS can still terminate this service; it is not a guaranteed alarm clock.
 */
class OrderRingService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var running = false
    private val activeOrderIds = mutableSetOf<String>()
    private var wakeLock: PowerManager.WakeLock? = null
    private val resolvedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_RESOLVE) return
            val orderId = intent.getStringExtra(EXTRA_ORDER_ID)?.trim().orEmpty()
            if (orderId.isNotEmpty()) activeOrderIds.remove(orderId)
            if (activeOrderIds.isEmpty()) stopRinging()
        }
    }
    private val stopBurst = Runnable { releasePlayer() }
    private val cycle = object : Runnable {
        override fun run() {
            playBurst()
            handler.postDelayed(this, 15_000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ContextCompat.registerReceiver(this, resolvedReceiver, IntentFilter(ACTION_RESOLVE), ContextCompat.RECEIVER_NOT_EXPORTED)
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            "hala_merchant_active_ring", "تنبيه طلب قيد الانتظار",
            NotificationManager.IMPORTANCE_LOW
        ))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_RESOLVE) {
            val orderId = intent.getStringExtra(EXTRA_ORDER_ID)?.trim().orEmpty()
            if (orderId.isNotEmpty()) activeOrderIds.remove(orderId)
            if (activeOrderIds.isEmpty()) stopRinging()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            val orderId = intent.getStringExtra(EXTRA_ORDER_ID)
            if (!orderId.isNullOrBlank()) {
                activeOrderIds.remove(orderId)
                if (activeOrderIds.isNotEmpty()) return START_NOT_STICKY
            } else {
                activeOrderIds.clear()
            }
            stopRinging()
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START) return START_NOT_STICKY
        intent.getStringExtra(EXTRA_ORDER_ID)?.takeIf { it.isNotBlank() }?.let { activeOrderIds.add(it) }
        val openIntent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, "hala_merchant_active_ring")
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("هلا طلب – طلب جديد")
            .setContentText("يوجد طلب ينتظر موافقتك أو رفضك")
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
        startForeground(8231, notification)
        if (!running) {
            running = true
            // Keep the CPU available while an active merchant alert is playing
            // behind the lock screen. This does not bypass Android's FGS start rules.
            try {
                val pm = getSystemService(POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HalaTalab:MerchantOrderRing")
                wakeLock?.acquire(60_000L)
            } catch (_: Exception) { wakeLock = null }
            cycle.run()
        }
        return START_NOT_STICKY
    }

    private fun stopRinging() {
        handler.removeCallbacks(cycle)
        releasePlayer()
        stopSelf()
    }

    private fun playBurst() {
        // Refresh a bounded CPU lock while the ring is active. A single
        // ten-minute acquisition could expire while an order is still pending.
        try {
            if (wakeLock?.isHeld != true) wakeLock?.acquire(60_000L)
        } catch (_: Exception) {}
        releasePlayer()
        try {
            val p = MediaPlayer()
            p.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            p.setDataSource(this, android.net.Uri.parse("android.resource://$packageName/${R.raw.hala_order_alert}"))
            p.isLooping = true
            p.prepare()
            p.start()
            player = p
            handler.postDelayed(stopBurst, 5_000L)
        } catch (_: Exception) { releasePlayer() }
    }

    private fun releasePlayer() {
        handler.removeCallbacks(stopBurst)
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
    }

    override fun onDestroy() {
        try { unregisterReceiver(resolvedReceiver) } catch (_: Exception) {}
        handler.removeCallbacks(cycle)
        releasePlayer()
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
        running = false
        super.onDestroy()
    }

    companion object {
        const val EXTRA_ORDER_ID = "order_id"
        const val ACTION_START = "com.halatalab.partners.START_ORDER_RING"
        const val ACTION_STOP = "com.halatalab.partners.STOP_ORDER_RING"
        const val ACTION_RESOLVE = "com.halatalab.partners.RESOLVE_ORDER_RING"
    }
}
