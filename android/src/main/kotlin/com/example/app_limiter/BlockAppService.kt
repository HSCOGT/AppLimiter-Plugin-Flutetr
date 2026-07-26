package com.example.app_limiter

import android.app.AppOpsManager
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Context.KEYGUARD_SERVICE
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import java.util.Calendar

const val CHANNEL_ID = "BlockAppService_Channel_ID"
const val NOTIFICATION_ID = 1

class BlockAppService : Service() {
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private val CHANNEL = "flutter_screentime"
    private var isOverlayDisplayed = false
    private var handler: Handler? = null
    private var blockingRunnable: Runnable? = null
    private var currentForegroundApp: String? = null
    private var isInitialized = false

    val params = WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.MATCH_PARENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT
    )

    fun isDeviceLocked(context: Context): Boolean {
        val keyguardManager = context.getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        return keyguardManager.isKeyguardLocked
    }

    fun getCurrentForegroundApp(context: Context): String? {
        val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val beginTime = endTime - 1000 * 10 // Last 10 seconds for more recent data

        val usageEvents = usageStatsManager.queryEvents(beginTime, endTime)
        var lastEvent: UsageEvents.Event? = null
        
        while (usageEvents.hasNextEvent()) {
            val event = UsageEvents.Event()
            usageEvents.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                lastEvent = event
            }
        }
        
        return lastEvent?.packageName
    }

    /** Reads the user's currently selected blocked packages from prefs. */
    private fun getBlockedPackages(): Set<String> {
        val prefs = getSharedPreferences(
            AppLimiterPrefs.PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        return prefs.getStringSet(AppLimiterPrefs.KEY_BLOCKED_PACKAGES, emptySet())
            ?: emptySet()
    }

    fun isBlockedAppInForeground(context: Context): Boolean {
        val foregroundApp = getCurrentForegroundApp(context)

        // Update current foreground app
        currentForegroundApp = foregroundApp

        return foregroundApp != null && getBlockedPackages().contains(foregroundApp)
    }

    private fun showOverlay() {
        try {
            if (!isOverlayDisplayed && overlayView?.windowToken == null) {
                windowManager?.addView(overlayView, params)
                isOverlayDisplayed = true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun hideOverlay() {
        try {
            if (isOverlayDisplayed && overlayView?.windowToken != null) {
                windowManager?.removeView(overlayView)
                isOverlayDisplayed = false
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun blockApps() {
        // The set of apps to block is read live from SharedPreferences inside the
        // blocking loop (see [isBlockedAppInForeground]), so selection changes take
        // effect without restarting the service.
        startBlockingLoop()
    }

    private fun startBlockingLoop() {
        handler = Handler(Looper.getMainLooper())
        
        blockingRunnable = object : Runnable {
            override fun run() {
                val sharedPreferences = getSharedPreferences("app_settings", Context.MODE_PRIVATE)
                val shouldBlock = sharedPreferences.getBoolean("Blocking", false)
                
                // Check permissions
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    if (!Settings.canDrawOverlays(this@BlockAppService) || !hasUsageStatsPermission(this@BlockAppService)) {
                        val editor = sharedPreferences.edit()
                        editor.putBoolean("Blocking", false)
                        editor.apply()
                        hideOverlay()
                        return
                    }
                }
                
                if (!shouldBlock) {
                    hideOverlay()
                    return
                }
                
                val isDeviceLocked = isDeviceLocked(this@BlockAppService)
                val isBlockedAppActive = isBlockedAppInForeground(this@BlockAppService)
                
                when {
                    isDeviceLocked -> {
                        // Device is locked, hide overlay
                        hideOverlay()
                    }
                    isBlockedAppActive -> {
                        // Blocked app is active, show overlay
                        showOverlay()
                    }
                    else -> {
                        // No blocked app is active, hide overlay
                        hideOverlay()
                    }
                }
                
                // Continue the loop with reduced delay for better responsiveness
                handler?.postDelayed(this, 200)
            }
        }
        
        handler?.post(blockingRunnable!!)
    }

    fun hasUsageStatsPermission(context: Context): Boolean {
        val appOpsManager = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOpsManager.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            android.os.Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    override fun onBind(intent: Intent): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        println("[DEBUG] onStartCommand()")

        // startForeground must be (re)called promptly on every start; it is safe
        // to invoke repeatedly.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "BlockAppService Channel", NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("BlockAppService")
            .setContentText("Service is running...")
            .build()

        startForeground(NOTIFICATION_ID, notification)

        // Inflate the overlay and start the blocking loop only once, even if the
        // service is started again while already running.
        if (!isInitialized) {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            overlayView = LayoutInflater.from(this).inflate(R.layout.block_overlay, null)
            isInitialized = true
            blockApps()
        }

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        
        // Clean up resources
        blockingRunnable?.let { handler?.removeCallbacks(it) }
        handler = null
        blockingRunnable = null
        isInitialized = false

        // Hide overlay if it's showing
        hideOverlay()

        println("[DEBUG] onDestroy()")
    }
}