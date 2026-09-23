package com.example.app_limiter

import android.app.AppOpsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Restores app blocking after a reboot, but only when the user left it enabled
 * and the permissions it depends on are still granted. Starting the service
 * unconditionally used to leave a permanent foreground notification with a
 * dead blocking loop behind it.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences(AppLimiterPrefs.PREFS_NAME, Context.MODE_PRIVATE)
        val blocking = prefs.getBoolean(AppLimiterPrefs.KEY_BLOCKING, false)
        val hasOverlay = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(context)
        val hasUsage = hasUsageStatsPermission(context)

        Log.d(TAG, "boot completed: blocking=$blocking overlay=$hasOverlay usage=$hasUsage")
        if (!blocking || !hasOverlay || !hasUsage) return

        AppLimiterPlugin.startBlockService(context)
    }

    private fun hasUsageStatsPermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private companion object {
        const val TAG = "AppLimiter"
    }
}
