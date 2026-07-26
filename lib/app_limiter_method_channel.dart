import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_app.dart';
import 'app_limiter_platform_interface.dart';

/// An implementation of [AppLimiterPlatform] that uses method channels.
class MethodChannelAppLimiter extends AppLimiterPlatform {
  /// The method channel used to interact with the native platform.
  final methodChannel = const MethodChannel('app_limiter');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  /// iOS-specific implementation for blocking and unblocking apps
  @override
  Future<String?> handleAppSelection(bool applyLocally) async {
    try {
      final result =
          await methodChannel.invokeMethod<String?>('handleAppSelection', {
        'applyLocally': applyLocally,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to block/Unbloc iOS app: ${e.message}');
      return null;
    }
  }

  @override
  Future<int> getBlockedAppCount() async {
    try {
      final result = await methodChannel.invokeMethod('getBlockedAppCount');
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to get blocked app count: ${e.message}');
      return 0;
    }
  }

  /// Requests iOS permissions through the native implementation
  @override
  Future<bool> requestIosPermission() async {
    try {
      final result = await methodChannel.invokeMethod('requestPermission');
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to get status: ${e.message}');
      return false;
    }
  }

  /// Requests iOS child device authorization through the native implementation
  @override
  Future<bool> requestIosChildDeviceAuthorization() async {
    try {
      final result =
          await methodChannel.invokeMethod('requestChildDeviceAuthorization');
      return result;
    } on PlatformException catch (e) {
      debugPrint(
          'Failed to request iOS child device authorization: ${e.message}');
      return false;
    }
  }

  @override
  Future<bool> isAutomaticWebFilterEnabledIos() async {
    try {
      final result =
          await methodChannel.invokeMethod('isAutomaticWebFilterEnabled');
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to get automatic web filter status: ${e.message}');
      return false;
    }
  }

  /// iOS-specific implementation for blocking and unblocking websites
  @override
  Future<void> setAutomaticWebFilterIos(bool enabled) async {
    try {
      await methodChannel.invokeMethod('setAutomaticWebFilter', {
        'enabled': enabled,
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to set automatic web filter: ${e.message}');
    }
  }

  /// Android-specific implementation for enabling/disabling the DNS web filter
  @override
  Future<bool> setAutomaticWebFilterAndroid(bool enabled) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'setAutomaticWebFilter',
        {'enabled': enabled},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to set Android web filter: ${e.message}');
      return false;
    }
  }

  /// Android-specific implementation for reading the DNS web filter state
  @override
  Future<bool> isAutomaticWebFilterEnabledAndroid() async {
    try {
      final result =
          await methodChannel.invokeMethod<bool>('isAutomaticWebFilterEnabled');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to get Android web filter status: ${e.message}');
      return false;
    }
  }

  @override
  Future<void> applyRemoteSettings(String jsonString) async {
    try {
      await methodChannel.invokeMethod('applyRemoteSettings', {
        'jsonString': jsonString,
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to apply remote settings: ${e.message}');
    }
  }

  /// Enumerates launchable Android apps for the selection picker
  @override
  Future<List<AndroidApp>> getInstalledAndroidApps() async {
    try {
      final result =
          await methodChannel.invokeMethod<List<dynamic>>('getInstalledApps');
      return (result ?? [])
          .map((e) => AndroidApp.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    } on PlatformException catch (e) {
      debugPrint('Failed to get installed Android apps: ${e.message}');
      return [];
    }
  }

  /// Reads the currently blocked Android package names
  @override
  Future<List<String>> getBlockedAndroidApps() async {
    try {
      final result =
          await methodChannel.invokeMethod<List<dynamic>>('getBlockedApps');
      return (result ?? []).map((e) => e as String).toList();
    } on PlatformException catch (e) {
      debugPrint('Failed to get blocked Android apps: ${e.message}');
      return [];
    }
  }

  /// Persists the selected Android package names to block
  @override
  Future<int> setBlockedAndroidApps(List<String> packageNames) async {
    try {
      final result = await methodChannel.invokeMethod<int>('setBlockedApps', {
        'packages': packageNames,
      });
      return result ?? packageNames.length;
    } on PlatformException catch (e) {
      debugPrint('Failed to set blocked Android apps: ${e.message}');
      return 0;
    }
  }

  /// Checks Android permission status through the native implementation
  @override
  Future<bool> isAndroidPermissionAllowed() async {
    try {
      final result = await methodChannel.invokeMethod('checkPermission');
      if (result == "approved") {
        return true;
      } else {
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to get status: ${e.message}');
      return false;
    }
  }

  /// Reports the live state of each Android app-blocking permission.
  @override
  Future<Map<String, bool>> getAndroidPermissionStatus() async {
    try {
      final result =
          await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getPermissionStatus',
      );
      return {
        'usageAccess': result?['usageAccess'] == true,
        'overlay': result?['overlay'] == true,
      };
    } on PlatformException catch (e) {
      debugPrint('Failed to get permission status: ${e.message}');
      return const {'usageAccess': false, 'overlay': false};
    }
  }

  /// Requests Android permissions through the native implementation
  @override
  Future<void> requestAndroidPermission() async {
    try {
      await methodChannel.invokeMethod('requestAuthorization');
    } on PlatformException catch (e) {
      debugPrint('Failed to request android permission app: ${e.message}');
    }
  }

  /// Opens the system settings screen for a single Android permission.
  @override
  Future<void> requestAndroidPermissionType(String type) async {
    try {
      await methodChannel.invokeMethod('requestPermissionType', {'type': type});
    } on PlatformException catch (e) {
      debugPrint('Failed to request android permission ($type): ${e.message}');
    }
  }

  /// Android-specific implementation for blocking apps
  @override
  Future<void> blockAndroidApps() async {
    try {
      await methodChannel.invokeMethod('blockApp');
    } on PlatformException catch (e) {
      debugPrint('Failed to block Android app: ${e.message}');
    }
  }

  /// Android-specific implementation for unblocking apps
  @override
  Future<void> unblockAndroidApps() async {
    try {
      await methodChannel.invokeMethod('unblockApp');
    } on PlatformException catch (e) {
      debugPrint('Failed to unblock Android app: ${e.message}');
    }
  }
}
