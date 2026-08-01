import 'package:app_limiter/app_limiter.dart';
import 'package:app_limiter/app_limiter_method_channel.dart';
import 'package:app_limiter/app_limiter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAppLimiterPlatform
    with MockPlatformInterfaceMixin
    implements AppLimiterPlatform {
  bool blockCalled = false;
  bool unblockCalled = false;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<String?> handleAppSelection(bool applyLocally) async {
    blockCalled = true;
    unblockCalled = false;
    return null;
  }

  @override
  Future<int> getBlockedAppCount() async {
    return 0;
  }

  @override
  Future<bool> requestIosPermission() async {
    return true;
  }

  @override
  Future<bool> requestIosChildDeviceAuthorization() async {
    return true;
  }

  @override
  Future<bool> isAutomaticWebFilterEnabledIos() async {
    return false;
  }

  @override
  Future<bool> setAutomaticWebFilterIos(bool enabled) async {
    return enabled;
  }

  @override
  Future<bool> setAutomaticWebFilterAndroid(bool enabled) async {
    return enabled;
  }

  @override
  Future<bool> isAutomaticWebFilterEnabledAndroid() async {
    return false;
  }

  @override
  Future<void> applyRemoteSettings(String jsonString) async {}

  @override
  Future<List<AndroidApp>> getInstalledAndroidApps() async {
    return const <AndroidApp>[];
  }

  @override
  Future<List<String>> getBlockedAndroidApps() async {
    return const <String>[];
  }

  @override
  Future<int> setBlockedAndroidApps(List<String> packageNames) async {
    return packageNames.length;
  }

  @override
  Future<bool> isAndroidPermissionAllowed() async {
    return true;
  }

  @override
  Future<Map<String, bool>> getAndroidPermissionStatus() async {
    return const {'usageAccess': true, 'overlay': true};
  }

  @override
  Future<void> requestAndroidPermission() async {
    blockCalled = true;
  }

  @override
  Future<void> requestAndroidPermissionType(String type) async {
    blockCalled = true;
  }

  @override
  Future<void> blockAndroidApps() async {
    blockCalled = true;
  }

  @override
  Future<void> unblockAndroidApps() async {
    blockCalled = true;
  }
}

void main() {
  final AppLimiterPlatform initialPlatform = AppLimiterPlatform.instance;

  test('$MethodChannelAppLimiter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAppLimiter>());
  });

  test('getPlatformVersion', () async {
    AppLimiter appLimiterPlugin = AppLimiter();
    MockAppLimiterPlatform fakePlatform = MockAppLimiterPlatform();
    AppLimiterPlatform.instance = fakePlatform;

    expect(await appLimiterPlugin.getPlatformVersion(), '42');
  });
}
