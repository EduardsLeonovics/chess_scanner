import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app's process alive while games are analyzed with the app in
/// the background, by running an Android foreground service with a
/// progress notification. The analysis itself stays in the app's isolate;
/// the service only holds the process (and a wake lock).
///
/// Does nothing on other platforms: iOS suspends the app regardless, and
/// the generator resumes its queue when the app comes back.
abstract final class BackgroundWork {
  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static const _stopButton = 'stop';

  /// White-on-transparent status-bar icon; the launcher icon would show as
  /// a solid square. Declared as meta-data in AndroidManifest.xml.
  static const _icon = NotificationIcon(
    metaDataName: 'com.chesshive.notification_icon',
    backgroundColor: Color(0xFF49B0FD),
  );
  static VoidCallback? _onStop;

  /// Call once, before [runApp].
  static void init() {
    if (!_supported) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'game_analysis',
        channelName: 'Game analysis',
        channelDescription: 'Shown while your games are being analyzed for puzzles.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback(_onData);
  }

  static void _onData(Object data) {
    if (data == _stopButton) _onStop?.call();
  }

  /// Shows the notification. [onStop] runs when its Stop button is tapped.
  static Future<void> start(String text, {required VoidCallback onStop}) async {
    if (!_supported) return;
    _onStop = onStop;
    try {
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await FlutterForegroundTask.startService(
        serviceId: 4401,
        notificationTitle: 'Analyzing your games',
        notificationText: text,
        notificationIcon: _icon,
        notificationButtons: const [NotificationButton(id: _stopButton, text: 'Stop')],
        callback: _startCallback,
      );
    } catch (e) {
      // Analysis still runs while the app is open.
      debugPrint('Foreground service unavailable: $e');
    }
  }

  static Future<void> update(String text) async {
    if (!_supported) return;
    try {
      await FlutterForegroundTask.updateService(notificationText: text);
    } catch (e) {
      debugPrint('Foreground service update failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!_supported) return;
    _onStop = null;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('Foreground service stop failed: $e');
    }
  }
}

@pragma('vm:entry-point')
void _startCallback() => FlutterForegroundTask.setTaskHandler(_RelayHandler());

/// Runs in the service's isolate: passes the Stop button back to the app.
class _RelayHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) => FlutterForegroundTask.sendDataToMain(id);

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}
