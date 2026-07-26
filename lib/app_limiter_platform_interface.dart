import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'android_app.dart';
import 'app_limiter_method_channel.dart';

/// The interface that implementations of app_limiter must implement.
///
/// Platform implementations should extend this class rather than implement it as `app_limiter`
/// does not consider newly added methods to be breaking changes. Extending this class
/// (using `extends`) ensures that the subclass will get the default implementation, while
/// platform implementations that `implements` this interface will be broken by newly added
/// [AppLimiterPlatform] methods.
abstract class AppLimiterPlatform extends PlatformInterface {
  /// Constructs a AppLimiterPlatform.
  AppLimiterPlatform() : super(token: _token);

  static final Object _token = Object();

  static AppLimiterPlatform _instance = MethodChannelAppLimiter();

  /// The default instance of [AppLimiterPlatform] to use.
  ///
  /// Defaults to [MethodChannelAppLimiter].
  static AppLimiterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AppLimiterPlatform] when they
  /// register themselves.
  static set instance(AppLimiterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Gets the platform version.
  Future<String?> getPlatformVersion();

  /// Handles blocking and unblocking operations for iOS apps.
  Future<String?> handleAppSelection(bool applyLocally);

  /// Gets the number of blocked apps.
  Future<int> getBlockedAppCount();

  /// Requests necessary permissions on iOS.
  Future<bool> requestIosPermission();

  /// Requests necessary child device authorization on iOS.
  Future<bool> requestIosChildDeviceAuthorization();

  /// Checks if automatic web filter is enabled on iOS.
  Future<bool> isAutomaticWebFilterEnabledIos();

  /// iOS-specific implementation for blocking and unblocking websites.
  /// Returns whether the filter reflects the requested state after the call.
  Future<bool> setAutomaticWebFilterIos(bool enabled);

  /// Enables/disables the Android DNS web filter. Returns whether the filter is
  /// active afterwards (false when VpnService consent is denied).
  Future<bool> setAutomaticWebFilterAndroid(bool enabled);

  /// Checks if the Android DNS web filter is currently active.
  Future<bool> isAutomaticWebFilterEnabledAndroid();

  /// iOS-specific implementation for applying remote settings
  Future<void> applyRemoteSettings(String jsonString);

  /// Returns every launchable Android app the user can choose to block.
  Future<List<AndroidApp>> getInstalledAndroidApps();

  /// Returns the package names the user has currently selected to block.
  Future<List<String>> getBlockedAndroidApps();

  /// Persists the set of Android package names to block, returning the count.
  Future<int> setBlockedAndroidApps(List<String> packageNames);

  /// Checks if required Android permissions are granted.
  Future<bool> isAndroidPermissionAllowed();

  /// Reports the live state of each Android app-blocking permission.
  ///
  /// Keys: `usageAccess` and `overlay`. Lets the UI show which permissions are
  /// still outstanding rather than a single combined flag.
  Future<Map<String, bool>> getAndroidPermissionStatus();

  /// Requests necessary Android permissions.
  Future<void> requestAndroidPermission();

  /// Opens the system settings screen for a single Android permission.
  ///
  /// [type] is one of `usageAccess` or `overlay`.
  Future<void> requestAndroidPermissionType(String type);

  /// Blocks specified Android apps.
  Future<void> blockAndroidApps();

  /// Unblocks previously blocked Android apps.
  Future<void> unblockAndroidApps();
}
