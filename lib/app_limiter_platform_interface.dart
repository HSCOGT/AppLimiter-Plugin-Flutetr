import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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
  Future<void> blockAndUnblockIOSApp();

  /// Requests necessary permissions on iOS.
  Future<bool> requestIosPermission();

  /// iOS-specific implementation for blocking and unblocking websites
  Future<void> blockWebsitesIos(List<String> domains);

  /// iOS-specific implementation for unblocking websites
  Future<void> unblockWebsitesIos();

  /// Checks if required Android permissions are granted.
  Future<bool> isAndroidPermissionAllowed();

  /// Requests necessary Android permissions.
  Future<void> requestAndroidPermission();

  /// Blocks specified Android apps.
  Future<void> blockAndroidApps();

  /// Unblocks previously blocked Android apps.
  Future<void> unblockAndroidApps();
}
