package com.example.app_limiter

import android.app.AppOpsManager
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.util.concurrent.Executors

const val CHANNEL_ID = "BlockAppService_Channel_ID"
const val NOTIFICATION_ID = 1

/**
 * Foreground service that enforces the user's app selection.
 *
 * A short polling loop on the main thread tracks the foreground package via
 * [UsageStatsManager] events and draws a full-screen overlay while a blocked
 * package is on top. Design notes:
 *
 * - The loop never exits without re-posting itself. A missing permission only
 *   hides the overlay and backs off; it never mutates the `Blocking` flag. Only
 *   `Blocking=false` (set by `unblockApp`) stops the service.
 * - [onStartCommand] (re)posts the loop on every start so a service that is
 *   already running can never be left with a dead loop.
 * - The foreground package is *remembered* between ticks. Each tick only looks
 *   at a short sliding window of events and keeps the previous value when the
 *   window is empty, so sitting in a blocked app keeps it blocked.
 * - Declared as a `specialUse` foreground service: `dataSync` is capped at 6h
 *   per day on Android 15+ and may not be started from BOOT_COMPLETED.
 */
class BlockAppService : Service() {
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var isOverlayDisplayed = false
    private val handler = Handler(Looper.getMainLooper())
    private var blockingRunnable: Runnable? = null
    private val seedExecutor = Executors.newSingleThreadExecutor()

    /** Last package known to be in the foreground, kept across ticks. */
    @Volatile
    private var currentForegroundApp: String? = null

    /** Whether we already logged the "permissions missing" state (avoid spam). */
    private var loggedMissingPermissions = false

    /**
     * Wall-clock time until which the overlay stays hidden after the user tapped
     * one of its actions, giving the launched home/app activity a moment to
     * come to the foreground before enforcement resumes.
     */
    private var suppressOverlayUntil = 0L

    private val overlayParams: WindowManager.LayoutParams by lazy {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).also {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                it.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    // ---------------------------------------------------------------------
    // Permissions / device state
    // ---------------------------------------------------------------------

    private fun isDeviceLocked(): Boolean {
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return keyguardManager.isKeyguardLocked
    }

    private fun hasOverlayPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private fun hasUsageStatsPermission(): Boolean {
        val appOpsManager = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOpsManager.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun prefs() = getSharedPreferences(AppLimiterPrefs.PREFS_NAME, Context.MODE_PRIVATE)

    private fun isBlockingEnabled(): Boolean = prefs().getBoolean(AppLimiterPrefs.KEY_BLOCKING, false)

    /** Reads the user's currently selected blocked packages from prefs. */
    private fun getBlockedPackages(): Set<String> =
        prefs().getStringSet(AppLimiterPrefs.KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()

    // ---------------------------------------------------------------------
    // Foreground detection
    // ---------------------------------------------------------------------

    /**
     * Returns the package of the most recent foreground event within
     * [beginTime, endTime], or null when there is none.
     */
    private fun latestForegroundPackage(beginTime: Long, endTime: Long): String? {
        if (beginTime >= endTime) return null
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val usageEvents = usageStatsManager.queryEvents(beginTime, endTime) ?: return null
        var latestPackage: String? = null
        var latestTime = Long.MIN_VALUE
        val event = UsageEvents.Event()
        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            // ACTIVITY_RESUMED (API 29+) shares its value with the deprecated
            // MOVE_TO_FOREGROUND, so one comparison covers both.
            if (event.eventType != UsageEvents.Event.MOVE_TO_FOREGROUND) continue
            val pkg = event.packageName ?: continue
            if (pkg == packageName) continue
            if (event.timeStamp >= latestTime) {
                latestTime = event.timeStamp
                latestPackage = pkg
            }
        }
        return latestPackage
    }

    /**
     * Updates [currentForegroundApp] from a short sliding window. The window
     * is re-queried every tick (idempotent, tolerant of events that land in
     * the usage-stats service a little late) and the previous value is kept
     * when the window holds no foreground event.
     */
    private fun refreshForegroundApp() {
        val now = System.currentTimeMillis()
        val latest = try {
            latestForegroundPackage(now - EVENT_WINDOW_MS, now)
        } catch (e: Exception) {
            Log.w(TAG, "queryEvents failed", e)
            null
        }
        if (latest != null && latest != currentForegroundApp) {
            Log.d(TAG, "foreground: $currentForegroundApp -> $latest")
            currentForegroundApp = latest
        }
    }

    /**
     * Seeds [currentForegroundApp] when the service (re)starts so a START_STICKY
     * restart while the user is already inside a blocked app is caught. Runs
     * off the main thread because the fallback scan is comparatively heavy.
     */
    private fun seedForegroundApp() {
        seedExecutor.execute {
            try {
                val now = System.currentTimeMillis()
                var seed = latestForegroundPackage(now - SEED_WINDOW_MS, now)
                if (seed == null) {
                    val usageStatsManager =
                        getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                    val stats = usageStatsManager.queryUsageStats(
                        UsageStatsManager.INTERVAL_DAILY,
                        now - SEED_FALLBACK_MS,
                        now,
                    )
                    seed = stats
                        ?.filter { it.lastTimeUsed > 0 && it.packageName != packageName }
                        ?.maxByOrNull { it.lastTimeUsed }
                        ?.packageName
                }
                if (seed != null && currentForegroundApp == null) {
                    currentForegroundApp = seed
                }
                Log.d(TAG, "seeded foreground app: $seed")
            } catch (e: Exception) {
                Log.w(TAG, "seeding foreground app failed", e)
            }
        }
    }

    // ---------------------------------------------------------------------
    // Overlay
    // ---------------------------------------------------------------------

    private fun ensureOverlayView() {
        if (windowManager == null) {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        }
        if (overlayView == null) {
            overlayView = LayoutInflater.from(this)
                .inflate(R.layout.block_overlay, null)
                .also { bindOverlayActions(it) }
        }
    }

    /**
     * Wires the block screen's actions. Both launch from the service while our
     * overlay window is visible, which is an allowed background-activity-start
     * exemption; failures are logged rather than crashing the service.
     */
    private fun bindOverlayActions(view: View) {
        val appLabel = try {
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (e: Exception) {
            "the app"
        }

        view.findViewById<TextView>(R.id.overlay_open_app_button)?.let { button ->
            button.text = "Open $appLabel"
            button.setOnClickListener {
                hideOverlay()
                val launch = packageManager.getLaunchIntentForPackage(packageName)
                if (launch == null) {
                    Log.w(TAG, "no launch intent for $packageName")
                    return@setOnClickListener
                }
                launch.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
                )
                startActivitySafely(launch, "open app")
            }
        }

        view.findViewById<TextView>(R.id.overlay_home_button)?.setOnClickListener {
            hideOverlay()
            val home = Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivitySafely(home, "go home")
        }
    }

    private fun startActivitySafely(intent: Intent, what: String) {
        suppressOverlayUntil = System.currentTimeMillis() + ACTION_GRACE_MS
        try {
            startActivity(intent)
            Log.d(TAG, "overlay action: $what")
        } catch (e: Exception) {
            Log.e(TAG, "overlay action failed: $what", e)
        }
    }

    private fun showOverlay() {
        try {
            val view = overlayView ?: return
            if (!isOverlayDisplayed && view.windowToken == null) {
                windowManager?.addView(view, overlayParams)
                isOverlayDisplayed = true
                Log.d(TAG, "overlay shown over $currentForegroundApp")
            }
        } catch (e: Exception) {
            Log.e(TAG, "failed to show overlay", e)
        }
    }

    private fun hideOverlay() {
        try {
            val view = overlayView ?: return
            if (isOverlayDisplayed && view.windowToken != null) {
                windowManager?.removeView(view)
                Log.d(TAG, "overlay hidden")
            }
        } catch (e: Exception) {
            Log.e(TAG, "failed to hide overlay", e)
        } finally {
            isOverlayDisplayed = false
        }
    }

    // ---------------------------------------------------------------------
    // Polling loop
    // ---------------------------------------------------------------------

    private fun startBlockingLoop() {
        blockingRunnable?.let { handler.removeCallbacks(it) }

        val runnable = object : Runnable {
            override fun run() {
                if (!isBlockingEnabled()) {
                    // unblockApp cleared the flag: tear down for good.
                    Log.d(TAG, "blocking disabled, stopping service")
                    hideOverlay()
                    stopSelf()
                    return
                }

                if (!hasOverlayPermission() || !hasUsageStatsPermission()) {
                    if (!loggedMissingPermissions) {
                        Log.w(
                            TAG,
                            "permissions missing (overlay=${hasOverlayPermission()}, " +
                                "usage=${hasUsageStatsPermission()}); waiting",
                        )
                        loggedMissingPermissions = true
                    }
                    hideOverlay()
                    handler.postDelayed(this, MISSING_PERMISSION_INTERVAL_MS)
                    return
                }
                if (loggedMissingPermissions) {
                    Log.d(TAG, "permissions restored, resuming enforcement")
                    loggedMissingPermissions = false
                }

                refreshForegroundApp()
                val foreground = currentForegroundApp
                val shouldShow = !isDeviceLocked() &&
                    System.currentTimeMillis() >= suppressOverlayUntil &&
                    foreground != null &&
                    getBlockedPackages().contains(foreground)

                if (shouldShow) showOverlay() else hideOverlay()

                handler.postDelayed(this, POLL_INTERVAL_MS)
            }
        }
        blockingRunnable = runnable
        handler.post(runnable)
    }

    // ---------------------------------------------------------------------
    // Service lifecycle
    // ---------------------------------------------------------------------

    override fun onBind(intent: Intent): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand(startId=$startId)")

        if (!startForegroundSafely()) {
            stopSelf()
            return START_NOT_STICKY
        }

        ensureOverlayView()
        if (currentForegroundApp == null) seedForegroundApp()
        // Always (re)start the loop: a running service whose loop died for any
        // reason is revived by the next blockApp call.
        startBlockingLoop()

        return START_STICKY
    }

    /**
     * Promotes the service to the foreground. Returns false when the system
     * refuses (e.g. background-start restrictions) so the caller can stop
     * cleanly instead of crashing the host app.
     */
    private fun startForegroundSafely(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App blocker",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.setShowBadge(false)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val appLabel = try {
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (e: Exception) {
            "App blocker"
        }
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(appLabel)
            .setContentText("App blocking is active")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed", e)
            false
        }
    }

    /**
     * Android 15+ time limit hook. `specialUse` services have no limit, but if
     * the system ever calls this we must stop promptly or the app is killed.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "onTimeout(startId=$startId, fgsType=$fgsType); stopping")
        hideOverlay()
        stopSelf()
        super.onTimeout(startId, fgsType)
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy()")
        blockingRunnable?.let { handler.removeCallbacks(it) }
        blockingRunnable = null
        hideOverlay()
        seedExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        const val TAG = "AppLimiter"
        /** Loop period while enforcement is active. */
        private const val POLL_INTERVAL_MS = 200L
        /** Loop period while waiting for the user to grant permissions. */
        private const val MISSING_PERMISSION_INTERVAL_MS = 2_000L
        /** Sliding window queried on every tick. */
        private const val EVENT_WINDOW_MS = 3_000L
        /** Window scanned once on start to recover the current foreground app. */
        private const val SEED_WINDOW_MS = 60_000L
        /** Fallback range for the daily-stats scan when the seed window is empty. */
        private const val SEED_FALLBACK_MS = 24L * 60 * 60 * 1000
        /** How long the overlay stays hidden after one of its buttons is tapped. */
        private const val ACTION_GRACE_MS = 1_500L
    }
}
