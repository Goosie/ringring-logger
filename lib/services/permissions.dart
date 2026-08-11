import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

/// Snapshot of the permissions the app needs to record in the background.
class PermissionStatus2 {
  const PermissionStatus2({
    required this.foregroundLocation,
    required this.backgroundLocation,
    required this.notifications,
    required this.ignoreBatteryOptimizations,
  });

  final bool foregroundLocation;
  final bool backgroundLocation;
  final bool notifications;
  final bool ignoreBatteryOptimizations;

  /// The app can record once foreground + background location are granted and
  /// notifications are allowed. Battery-optimization is strongly recommended but
  /// not strictly blocking.
  bool get canRecord =>
      foregroundLocation && backgroundLocation && notifications;

  bool get allGood => canRecord && ignoreBatteryOptimizations;
}

/// Central place for the Android 11+ two-step permission flow.
class Permissions {
  static Future<PermissionStatus2> check() async {
    final fg = await Permission.locationWhenInUse.isGranted;
    final bg = await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;
    final battery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    return PermissionStatus2(
      foregroundLocation: fg,
      backgroundLocation: bg,
      notifications: notif,
      ignoreBatteryOptimizations: battery,
    );
  }

  /// Step 1: foreground (when-in-use) location. Returns true if granted.
  static Future<bool> requestForegroundLocation() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  /// Step 2: background ("allow all the time") location. Android requires this
  /// to be requested *after* foreground is already granted, and it usually
  /// sends the user to a settings page — hence the explanation screen before.
  static Future<bool> requestBackgroundLocation() async {
    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  /// Step 3: POST_NOTIFICATIONS (Android 13+). On older versions this resolves
  /// as granted automatically.
  static Future<bool> requestNotifications() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Opens the system dialog to exempt the app from battery optimization.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return true;
    return FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
}
