package com.example.app_limiter

import android.app.*
import android.app.usage.*
import android.content.*
import android.content.pm.*
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.net.VpnService
import android.os.*
import android.provider.Settings
import java.io.ByteArrayOutputStream
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import androidx.annotation.NonNull
import kotlinx.coroutines.*
import android.Manifest
import java.util.Calendar
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding


/**
 * AppLimiterPlugin: Main plugin class that handles the communication between Flutter and Android
 * 
 * This plugin provides functionality for:
 * - Getting platform version
 * - Managing app usage permissions
 * - Blocking and unblocking apps
 * - Handling system overlay permissions
 * 
 * Implements:
 * - FlutterPlugin: For plugin registration and lifecycle
 * - MethodCallHandler: For handling method calls from Flutter
 * - ActivityAware: For accessing Activity context and permissions
 */
class AppLimiterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    // Pending Flutter result awaiting the VpnService consent dialog.
    private var pendingVpnResult: Result? = null
    // Coroutine scope for background tasks
    var job = Job()
    val scope = CoroutineScope(Dispatchers.Default + job)
    // Handler used to deliver method-channel results back on the main thread.
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        /** SharedPreferences file shared with [BlockAppService]. */
        const val PREFS_NAME = "app_settings"
        /** Whether blocking enforcement is currently active. */
        const val KEY_BLOCKING = "Blocking"
        /** Set of package names the user has chosen to block. */
        const val KEY_BLOCKED_PACKAGES = "BlockedPackages"
        /** Whether the DNS web filter (VpnService) is currently active. */
        const val KEY_WEB_FILTER_ENABLED = "WebFilterEnabled"
        /** Largest icon dimension (px) returned to Flutter for the picker. */
        const val MAX_ICON_SIZE_PX = 96
        /** Request code for the VpnService consent dialog. */
        private const val VPN_REQUEST_CODE = 7001
    }

    /** Reads the user's currently selected blocked packages. */
    private fun blockedPackages(): Set<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()
    }

    /**
     * Enumerates every launchable app (excluding this host app), returning a
     * list of maps with `packageName`, `appName` and a PNG `icon` byte array.
     * Runs on a background dispatcher because loading icons is expensive.
     */
    private fun getInstalledApps(): List<Map<String, Any?>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any?>>()

        for (info in resolveInfos) {
            val packageName = info.activityInfo.packageName
            // De-duplicate (an app can expose multiple launcher activities) and
            // never let the user block the host app itself.
            if (packageName == context.packageName || !seen.add(packageName)) {
                continue
            }
            val appName = info.loadLabel(pm).toString()
            val icon = try {
                drawableToPngBytes(info.loadIcon(pm))
            } catch (e: Exception) {
                null
            }
            apps.add(
                mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "icon" to icon,
                )
            )
        }

        apps.sortBy { (it["appName"] as String).lowercase() }
        return apps
    }

    /** Renders a launcher [Drawable] to a size-capped PNG byte array. */
    private fun drawableToPngBytes(drawable: Drawable): ByteArray? {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: MAX_ICON_SIZE_PX
            val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: MAX_ICON_SIZE_PX
            val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }

        val scaled = if (bitmap.width > MAX_ICON_SIZE_PX || bitmap.height > MAX_ICON_SIZE_PX) {
            val ratio = MAX_ICON_SIZE_PX.toFloat() / maxOf(bitmap.width, bitmap.height)
            Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * ratio).toInt().coerceAtLeast(1),
                (bitmap.height * ratio).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            bitmap
        }

        return ByteArrayOutputStream().use { stream ->
            scaled.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }
    }

    // Helper methods from MainActivity.kt
    /**
     * Checks if the app has permission to draw overlays
     * Required for displaying blocking UI on top of other apps
     * 
     * @param activity The current activity context
     * @return Boolean indicating if permission is granted
     */
    private fun checkDrawOverlayPermission(activity: Activity): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(activity)
        } else {
            true
        }
    }

    /**
     * Requests permission to draw overlays
     * Opens system settings if permission is not granted
     * 
     * @param activity The current activity context
     * @param requestCode Request code for permission result
     * @return Boolean indicating if permission was already granted
     */
    private fun requestDrawOverlayPermission(activity: Activity, requestCode: Int): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(activity)) {
                val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + activity.packageName))
                activity.startActivityForResult(intent, requestCode)
                return false
            }
        }
        return true
    }

    /**
     * Checks if the app has permission to query all packages
     * Required for Android 11+ to access package information
     * 
     * @param context Application context
     * @return Boolean indicating if permission is granted
     */
    private fun checkQueryAllPackagesPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            PackageManager.PERMISSION_GRANTED == context.checkSelfPermission(Manifest.permission.QUERY_ALL_PACKAGES)
        } else {
            true
        }
    }

    /**
     * Requests permission to query all packages
     * Required for Android 11+ functionality
     * 
     * @param activity The current activity context
     * @return Boolean indicating if permission was already granted
     */
    private fun requestQueryAllPackagesPermission(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (activity.checkSelfPermission(Manifest.permission.QUERY_ALL_PACKAGES) != PackageManager.PERMISSION_GRANTED) {
                activity.requestPermissions(arrayOf(Manifest.permission.QUERY_ALL_PACKAGES), 2)
                return false
            }
        }
        return true
    }

    /**
     * Checks if the app has usage stats permission
     * Required for monitoring app usage
     * 
     * @param context Application context
     * @return Boolean indicating if permission is granted
     */
    private fun hasUsageStatsPermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), context.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Requests usage stats permission
     * Opens system settings for usage access
     * 
     * @param context Application context
     */
    private fun requestUsageStatsPermission(context: Context) {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        context.startActivity(intent)
    }

    /**
     * Checks if a service is currently running
     * Used to monitor the blocking service status
     * 
     * @param serviceClassName The full class name of the service to check
     * @param context Application context
     * @return Boolean indicating if the service is running
     */
    private fun isServiceRunning(serviceClassName: String, context: Context): Boolean {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        for (service in activityManager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClassName == service.service.className) {
                return true
            }
        }
        return false
    }

    /**
     * Sets up an alarm for scheduled app blocking
     * Used to automatically start blocking at specific times
     * 
     * @param hour Hour of the day (24-hour format)
     * @param minute Minute of the hour
     * @param second Second of the minute
     */
    private fun setAlarm(hour: Int, minute: Int, second: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val calendar = Calendar.getInstance().apply {
            timeInMillis = System.currentTimeMillis()
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, second)
        }
        val intent = Intent(context, BlockAppService::class.java)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getBroadcast(context, 0, intent, pendingIntentFlags)
        alarmManager.setExact(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pendingIntent)
    }

    /**
     * Enables the DNS web filter. Requests one-time VpnService consent if it
     * hasn't been granted; [result] resolves true once the filter is running,
     * false if consent is denied.
     */
    private fun enableWebFilter(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is null", null)
            return
        }
        val consentIntent = VpnService.prepare(currentActivity)
        if (consentIntent == null) {
            startWebFilterService()
            result.success(true)
        } else {
            if (pendingVpnResult != null) {
                result.error("VPN_BUSY", "A VPN consent request is already in progress", null)
                return
            }
            pendingVpnResult = result
            currentActivity.startActivityForResult(consentIntent, VPN_REQUEST_CODE)
        }
    }

    private fun disableWebFilter() {
        val intent = Intent(context, WebFilterVpnService::class.java).apply {
            action = WebFilterVpnService.ACTION_STOP
        }
        context.startService(intent)
    }

    private fun startWebFilterService() {
        val intent = Intent(context, WebFilterVpnService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_REQUEST_CODE) return false
        val result = pendingVpnResult
        pendingVpnResult = null
        if (resultCode == Activity.RESULT_OK) {
            startWebFilterService()
            result?.success(true)
        } else {
            result?.success(false)
        }
        return true
    }

    // Flutter plugin lifecycle methods
    /**
     * Called when the plugin is attached to the Flutter engine
     * Sets up the method channel and context
     */
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "app_limiter")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    /**
     * Handles method calls from Flutter
     * Implements all the platform-specific functionality
     * 
     * Supported methods:
     * - getPlatformVersion: Returns Android version
     * - blockApp: Starts the app blocking service
     * - unblockApp: Stops the app blocking service
     * - checkPermission: Checks all required permissions
     * - requestAuthorization: Requests all required permissions
     */
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }

            "blockApp" -> {
                val sharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                sharedPreferences.edit().putBoolean(KEY_BLOCKING, true).apply()
                val intent = Intent(context, BlockAppService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                result.success(null)
            }

            "unblockApp" -> {
                val sharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                sharedPreferences.edit().putBoolean(KEY_BLOCKING, false).apply()
                val intent = Intent(context, BlockAppService::class.java)
                context.stopService(intent)
                result.success(null)
            }

            "getInstalledApps" -> {
                scope.launch {
                    val apps = try {
                        getInstalledApps()
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("INSTALLED_APPS_ERROR", e.message, null)
                        }
                        return@launch
                    }
                    mainHandler.post { result.success(apps) }
                }
            }

            "getBlockedApps" -> {
                result.success(blockedPackages().toList())
            }

            "setBlockedApps" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                val sharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                sharedPreferences.edit()
                    .putStringSet(KEY_BLOCKED_PACKAGES, packages.toSet())
                    .apply()
                result.success(packages.size)
            }

            "getBlockedAppCount" -> {
                result.success(blockedPackages().size)
            }

            "isAutomaticWebFilterEnabled" -> {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                result.success(prefs.getBoolean(KEY_WEB_FILTER_ENABLED, false))
            }

            "setAutomaticWebFilter" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                if (enabled) {
                    enableWebFilter(result)
                } else {
                    disableWebFilter()
                    result.success(false)
                }
            }

            // Remote settings use opaque iOS tokens with no Android equivalent;
            // enforcement is local-only for now.
            "applyRemoteSettings" -> {
                result.success(null)
            }

            "checkPermission" -> {
                val hasOverlayPermission = activity?.let { checkDrawOverlayPermission(it) } ?: false
                val hasQueryPermission = activity?.let { requestQueryAllPackagesPermission(it) } ?: false
                val hasUsageStatsPermission = context.let { hasUsageStatsPermission(it) }

                if (hasOverlayPermission && hasQueryPermission && hasUsageStatsPermission) {
                    result.success("approved")
                } else {
                    result.success("denied")
                }
            }

            "requestAuthorization" -> {
    val currentActivity = activity
    if (currentActivity == null) {
        result.error("NO_ACTIVITY", "Activity is null", null)
        return
    }
    val hasOverlayPermission = checkDrawOverlayPermission(currentActivity)
    val hasQueryPermission = checkQueryAllPackagesPermission(context)
    val hasUsageStatsPermission = hasUsageStatsPermission(context)

    when {
        !hasOverlayPermission -> {
            requestDrawOverlayPermission(currentActivity, 1234)
            result.success("overlay_permission_requested")
        }
        !hasQueryPermission -> {
            requestQueryAllPackagesPermission(currentActivity)
            result.success("query_permission_requested")
        }
        !hasUsageStatsPermission -> {
            requestUsageStatsPermission(currentActivity)
            result.success("usage_stats_permission_requested")
        }
        else -> {
            result.success("all_permissions_granted")
        }
    }
}


            else -> result.notImplemented()
        }
    }

    /**
     * Called when the plugin is detached from the Flutter engine
     * Cleans up the method channel
     */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /**
     * Called when the plugin is attached to an Activity
     * Required for permission handling and UI interactions
     */
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    /**
     * Called when the plugin is detached from an Activity
     * Cleans up the activity reference
     */
    override fun onDetachedFromActivity() {
        activity = null
    }

    /**
     * Called when the plugin is reattached to an Activity after configuration changes
     * Updates the activity reference
     */
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    /**
     * Called when the plugin is detached from an Activity during configuration changes
     * Cleans up the activity reference
     */
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
    
}
