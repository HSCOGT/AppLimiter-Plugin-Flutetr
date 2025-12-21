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
  Future<void> handleAppSelection(bool applyLocally) async {
    blockCalled = true;
    unblockCalled = false;
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
  Future<bool> isAndroidPermissionAllowed() async {
    return true;
  }

  @override
  Future<void> requestAndroidPermission() async {
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
