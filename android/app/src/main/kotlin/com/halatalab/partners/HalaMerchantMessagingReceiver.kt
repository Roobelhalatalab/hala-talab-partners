package com.halatalab.partners

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver

/** Keeps FlutterFire delivery intact; attempts merchant-only ring from FCM. */
class HalaMerchantMessagingReceiver : FlutterFirebaseMessagingReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // FlutterFire must always receive the original message, including driver pushes.
        super.onReceive(context, intent)
        try {
            val prefs = context.getSharedPreferences("hala_native_merchant_ring", Context.MODE_PRIVATE)
            val merchantStore = prefs.getString("store_id", null) ?: return
            if (!prefs.getBoolean("enabled", false)) return
            val type = intent.getStringExtra("notification_type") ?: return
            val store = intent.getStringExtra("store_id") ?: return
            val order = intent.getStringExtra("order_id") ?: return
            if (store != merchantStore || order.isBlank()) return
            // FCM can deliver an older new_order after its resolution event.
            // Remember recently resolved IDs to avoid restarting a stale alarm.
            val resolved = context.getSharedPreferences("hala_resolved_merchant_orders", Context.MODE_PRIVATE)
            val resolvedAt = resolved.getLong(order, 0L)
            if (type == "merchant_order_resolved") {
                resolved.edit().putLong(order, System.currentTimeMillis()).apply()
                // Broadcast to the already-running ring service; starting a
                // background service solely to stop it can be blocked by Android.
                context.sendBroadcast(Intent(OrderRingService.ACTION_RESOLVE)
                    .setPackage(context.packageName)
                    .putExtra(OrderRingService.EXTRA_ORDER_ID, order))
                return
            }
            if (type != "new_order") return
            if (resolvedAt > 0L && System.currentTimeMillis() - resolvedAt < 86_400_000L) return
            // Android can reject foreground-service starts from the background.
            val start = Intent(context, OrderRingService::class.java)
                .setAction(OrderRingService.ACTION_START)
                .putExtra(OrderRingService.EXTRA_ORDER_ID, order)
            ContextCompat.startForegroundService(context, start)
        } catch (_: Exception) {
            // Never interfere with standard push delivery.
        }
    }
}
