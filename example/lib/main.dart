import 'dart:async';
import 'dart:developer';

import 'package:app_limiter/app_limiter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _appLimiterPlugin = AppLimiter();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Initialize platform state
  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion = await _appLimiterPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  Future<void> handleAppSelection(bool applyLocally) async {
    try {
      await _appLimiterPlugin.handleAppSelection(applyLocally);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<bool> requestIosPermission() async {
    try {
      final result = await _appLimiterPlugin.requestIosPermission();
      log(result.toString(), name: 'Permission Status');
      return result;
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<bool> checkAndroidPermission() async {
    try {
      final result = await _appLimiterPlugin.isAndroidPermissionAllowed();
      log(result.toString(), name: 'Permission Status');
      return result;
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<void> requestAndroidPermission() async {
    try {
      await _appLimiterPlugin.requestAndroidPermission();
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<void> blockAndroidApps() async {
    try {
      await _appLimiterPlugin.blocAndroidApp();
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<void> unBlockAndroidApps() async {
    try {
      await _appLimiterPlugin.unblocAndroidApp();
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Running on: $_platformVersion\n'),
                  ElevatedButton(
                    onPressed: () => requestIosPermission(),
                    child: const Text('Request IOS Permission'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => blockOrUnblocIosApp(),
                    child: const Text('Block iOS App'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => checkAndroidPermission(),
                    child: const Text('Check Android Permission'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => requestAndroidPermission(),
                    child: const Text('Request Android Permission'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => blockAndroidApps(),
                    child: const Text('Block Android Apps'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => unBlockAndroidApps(),
                    child: const Text('Un-Block Android Apps'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
