import 'android_app.dart';
import 'app_limiter_platform_interface.dart';

export 'android_app.dart';

/// A Flutter plugin for implementing app usage limitations and restrictions on iOS and Android platforms.
///
/// This plugin provides functionality to:
/// * Block and unblock apps on iOS devices
/// * Block and unblock apps on Android devices
/// * Handle platform-specific permissions
/// * Check platform version and compatibility
class AppLimiter {
  /// Gets the current platform version.
  ///
  /// Returns a [Future] that completes with the platform version as a [String],
  /// or null if the platform version could not be determined.
  Future<String?> getPlatformVersion() {
    return AppLimiterPlatform.instance.getPlatformVersion();
  }

  /// Toggles the block state of an iOS app.
  ///
  /// This method handles both blocking and unblocking operations for iOS apps.
  /// It uses the Screen Time API on iOS to manage app restrictions.
  /// Throws a [PlatformException] if the operation fails.
  Future<String?> handleAppSelection(bool applyLocally) {
    return AppLimiterPlatform.instance.handleAppSelection(applyLocally);
  }

  /// Gets the number of blocked apps.
  Future<int> getBlockedAppCount() {
    return AppLimiterPlatform.instance.getBlockedAppCount();
  }

  /// Requests necessary permissions for app limiting functionality on iOS.
  ///
  /// Returns a [Future<bool>] that completes with:
  /// * true - if permissions were successfully granted
  /// * false - if permissions were denied or the request failed
  Future<bool> requestIosPermission() {
    return AppLimiterPlatform.instance.requestIosPermission();
  }

  /// Requests necessary child device authorization on iOS.
  ///
  /// Returns a [Future<bool>] that completes with:
  /// * true - if child device authorization was successfully granted
  /// * false - if child device authorization was denied or the request failed
  Future<bool> requestIosChildDeviceAuthorization() {
    return AppLimiterPlatform.instance.requestIosChildDeviceAuthorization();
  }

  /// Checks if automatic web filter is enabled on iOS.
  Future<bool> isAutomaticWebFilterEnabledIos() {
    return AppLimiterPlatform.instance.isAutomaticWebFilterEnabledIos();
  }

  /// iOS-specific implementation for blocking websites
  Future<void> setAutomaticWebFilterIos(bool enabled) {
    return AppLimiterPlatform.instance.setAutomaticWebFilterIos(enabled);
  }

  /// Enables or disables the Android DNS web filter.
  ///
  /// The first enable triggers Android's one-time VpnService consent dialog.
  /// Returns whether the filter is active afterwards — false if the user
  /// declines consent.
  Future<bool> setAutomaticWebFilterAndroid(bool enabled) {
    return AppLimiterPlatform.instance.setAutomaticWebFilterAndroid(enabled);
  }

  /// Checks whether the Android DNS web filter is currently active.
  Future<bool> isAutomaticWebFilterEnabledAndroid() {
    return AppLimiterPlatform.instance.isAutomaticWebFilterEnabledAndroid();
  }

  /// iOS-specific implementation for applying remote settings
  Future<void> applyRemoteSettings(String jsonString) {
    return AppLimiterPlatform.instance.applyRemoteSettings(jsonString);
  }

  /// Returns every launchable Android app the user can choose to block.
  ///
  /// Each [AndroidApp] carries its package name, label and (when available) its
  /// launcher icon, ready to render in a selection picker.
  Future<List<AndroidApp>> getInstalledAndroidApps() {
    return AppLimiterPlatform.instance.getInstalledAndroidApps();
  }

  /// Returns the package names currently selected for blocking on Android.
  ///
  /// Useful for pre-checking the picker with the existing selection.
  Future<List<String>> getBlockedAndroidApps() {
    return AppLimiterPlatform.instance.getBlockedAndroidApps();
  }

  /// Persists the set of Android package names to block.
  ///
  /// Returns the number of apps stored. The running blocking service reads this
  /// selection live, so changes take effect immediately.
  Future<int> setBlockedAndroidApps(List<String> packageNames) {
    return AppLimiterPlatform.instance.setBlockedAndroidApps(packageNames);
  }

  /// Checks if the required Android permissions are granted.
  ///
  /// Returns a [Future<bool>] that completes with:
  /// * true - if all required permissions are granted
  /// * false - if any required permission is missing
  Future<bool> isAndroidPermissionAllowed() {
    return AppLimiterPlatform.instance.isAndroidPermissionAllowed();
  }

  /// Reports the live state of each Android app-blocking permission.
  ///
  /// Returns a map with `usageAccess` and `overlay` booleans, so the UI can
  /// show which permissions are still outstanding rather than a single flag.
  Future<Map<String, bool>> getAndroidPermissionStatus() {
    return AppLimiterPlatform.instance.getAndroidPermissionStatus();
  }

  /// Opens the system settings screen for a single Android permission.
  ///
  /// [type] is one of `usageAccess` or `overlay`. Lets the UI request each
  /// permission from its own row.
  Future<void> requestAndroidPermissionType(String type) {
    return AppLimiterPlatform.instance.requestAndroidPermissionType(type);
  }

  /// Requests necessary permissions for app limiting functionality on Android.
  ///
  /// This method prompts the user to grant the required permissions for
  /// app usage access and other necessary Android permissions.
  /// Throws a [PlatformException] if the permission request fails.
  Future<void> requestAndroidPermission() {
    return AppLimiterPlatform.instance.requestAndroidPermission();
  }

  /// Blocks the specified Android app.
  ///
  /// Uses Android's UsageStats API to implement app blocking functionality.
  /// Throws a [PlatformException] if the blocking operation fails.
  Future<void> blocAndroidApp() {
    return AppLimiterPlatform.instance.blockAndroidApps();
  }

  /// Unblocks a previously blocked Android app.
  ///
  /// Removes usage restrictions from the specified Android app.
  /// Throws a [PlatformException] if the unblocking operation fails.
  Future<void> unblocAndroidApp() {
    return AppLimiterPlatform.instance.unblockAndroidApps();
  }
}
