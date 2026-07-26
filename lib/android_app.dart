import 'dart:typed_data';

/// A launchable Android application that can be selected for blocking.
class AndroidApp {
  /// The application's package name, e.g. `com.instagram.android`.
  final String packageName;

  /// The user-visible application label.
  final String appName;

  /// The app's launcher icon as PNG bytes, or null if it couldn't be loaded.
  final Uint8List? icon;

  const AndroidApp({
    required this.packageName,
    required this.appName,
    this.icon,
  });

  /// Builds an [AndroidApp] from the map returned by the platform channel.
  factory AndroidApp.fromMap(Map<dynamic, dynamic> map) {
    return AndroidApp(
      packageName: map['packageName'] as String,
      appName: map['appName'] as String? ?? map['packageName'] as String,
      icon: map['icon'] as Uint8List?,
    );
  }
}
