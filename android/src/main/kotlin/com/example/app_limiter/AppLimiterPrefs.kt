package com.example.app_limiter

/**
 * SharedPreferences file and keys shared between [AppLimiterPlugin] and its
 * services ([BlockAppService], [WebFilterVpnService]).
 *
 * These live in a standalone object rather than on the plugin's companion so
 * the services don't reference [AppLimiterPlugin] — the plugin already
 * references the services, and a cross-file cycle triggers nondeterministic
 * "unresolved reference" failures under the K2 Kotlin compiler.
 */
object AppLimiterPrefs {
    /** SharedPreferences file name. */
    const val PREFS_NAME = "app_settings"
    /** Whether app-blocking enforcement is currently active. */
    const val KEY_BLOCKING = "Blocking"
    /** Set of package names the user has chosen to block. */
    const val KEY_BLOCKED_PACKAGES = "BlockedPackages"
    /** Whether the DNS web filter (VpnService) is currently active. */
    const val KEY_WEB_FILTER_ENABLED = "WebFilterEnabled"
}
