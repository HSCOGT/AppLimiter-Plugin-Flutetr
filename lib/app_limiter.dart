import 'app_limiter_platform_interface.dart';

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
  Future<void> blockAndUnblockIOSApp() {
    return AppLimiterPlatform.instance.blockAndUnblockIOSApp();
  }

  /// Requests necessary permissions for app limiting functionality on iOS.
  ///
  /// Returns a [Future<bool>] that completes with:
  /// * true - if permissions were successfully granted
  /// * false - if permissions were denied or the request failed
  Future<bool> requestIosPermission() {
    return AppLimiterPlatform.instance.requestIosPermission();
  }

  /// iOS-specific implementation for blocking and unblocking websites
  Future<void> blockWebsitesIos(List<String> domains) {
    return AppLimiterPlatform.instance.blockWebsitesIos(domains);
  }

  /// iOS-specific implementation for unblocking websites
  Future<void> unblockWebsitesIos() {
    return AppLimiterPlatform.instance.unblockWebsitesIos();
  }

  /// Checks if the required Android permissions are granted.
  ///
  /// Returns a [Future<bool>] that completes with:
  /// * true - if all required permissions are granted
  /// * false - if any required permission is missing
  Future<bool> isAndroidPermissionAllowed() {
    return AppLimiterPlatform.instance.isAndroidPermissionAllowed();
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
