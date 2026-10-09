import 'package:flutter/services.dart';

/// Bridge to the Android side: the foreground service that keeps SSH sockets
/// alive in the background, and session notifications.
class BackgroundKeepAlive {
  static const _channel = MethodChannel('nabby/keepalive');
  static bool _running = false;

  /// [onDisconnectAll] runs when the user taps "Disconnect all" in the notification.
  static void init({required void Function() onDisconnectAll}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'disconnectAll') onDisconnectAll();
    });
  }

  static Future<void> update(int connections, {required bool enabled}) async {
    try {
      if (enabled && connections > 0) {
        await _channel.invokeMethod('start', {'count': connections});
        _running = true;
      } else if (_running) {
        await _channel.invokeMethod('stop');
        _running = false;
      }
    } catch (_) {}
  }

  /// Shows an alert notification, e.g. when a session drops while the app is in the background.
  static Future<void> notify(String title, String text) async {
    try {
      await _channel.invokeMethod('notify', {'title': title, 'text': text});
    } catch (_) {}
  }
}
