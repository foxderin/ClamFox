import 'package:flutter/services.dart';

/// Bridge to the GTK runner that owns the application window.
///
/// Backed by the `ai.clamfox/window` method channel registered in
/// `linux/runner/my_application.cc`.
class WindowController {
  WindowController._();
  static const _channel = MethodChannel('ai.clamfox/window');

  static Future<void> minimize() => _channel.invokeMethod('minimize');
  static Future<void> toggleMaximize() =>
      _channel.invokeMethod('toggleMaximize');
  static Future<void> close() => _channel.invokeMethod('close');
  static Future<void> startDrag() => _channel.invokeMethod('startDrag');

  static Future<bool> isMaximized() async {
    final result = await _channel.invokeMethod<bool>('isMaximized');
    return result ?? false;
  }
}
