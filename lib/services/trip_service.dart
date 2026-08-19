import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'recording_task_handler.dart';

/// UI-side wrapper around the foreground service. All calls here run in the main
/// isolate; the actual recording happens in [RecordingTaskHandler].
class TripService {
  /// Configure the foreground task once (channel, notification, event interval).
  /// Safe to call multiple times.
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ringring_logger_channel',
        channelName: 'RingRing Logger meting',
        channelDescription: 'Actief zolang een rit wordt opgenomen.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Fire onRepeatEvent every second; the handler uses counters for the
        // 60s battery sample and 30s crash-recovery write.
        eventAction: ForegroundTaskEventAction.repeat(1000),
        allowWakeLock: true, // keep CPU on with screen off / phone in pocket
        allowWifiLock: false,
        autoRunOnBoot: false,
      ),
    );
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  /// Persists config, then starts the location foreground service.
  static Future<ServiceRequestResult> start({
    required String id,
    required String deviceLabel,
    required String note,
    required String modality,
    required String devicePlacement,
    required String vehicleClass,
    required String phonePlacement,
    required String routeId,
    required int runIndex,
  }) async {
    await FlutterForegroundTask.saveData(key: kCfgId, value: id);
    await FlutterForegroundTask.saveData(key: kCfgDeviceLabel, value: deviceLabel);
    await FlutterForegroundTask.saveData(key: kCfgNote, value: note);
    await FlutterForegroundTask.saveData(key: kCfgModality, value: modality);
    await FlutterForegroundTask.saveData(
        key: kCfgDevicePlacement, value: devicePlacement);
    await FlutterForegroundTask.saveData(key: kCfgVehicleClass, value: vehicleClass);
    await FlutterForegroundTask.saveData(
        key: kCfgPhonePlacement, value: phonePlacement);
    await FlutterForegroundTask.saveData(key: kCfgRouteId, value: routeId);
    await FlutterForegroundTask.saveData(key: kCfgRunIndex, value: runIndex);

    return FlutterForegroundTask.startService(
      serviceId: 42,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'RingRing Logger meet',
      notificationText: 'Meting loopt…',
      callback: startRecordingCallback,
    );
  }

  /// Ask the handler to finalize the recording (writes last_trip.json, deletes
  /// active_trip.json, replies with an 'stopped' event).
  static void requestStop() {
    FlutterForegroundTask.sendDataToTask({'command': 'stop'});
  }

  /// Register a modality switch within the running recording.
  static void switchModality(String modalityCode) {
    FlutterForegroundTask.sendDataToTask(
      {'command': 'switch', 'modality': modalityCode},
    );
  }

  /// Register a device-placement switch within the running recording.
  static void switchPlacement(String placementCode) {
    FlutterForegroundTask.sendDataToTask(
      {'command': 'switchPlacement', 'placement': placementCode},
    );
  }

  static Future<ServiceRequestResult> stopService() =>
      FlutterForegroundTask.stopService();
}
