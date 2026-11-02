import 'dart:io';

import 'package:flutter/services.dart';

/// 屏幕常亮控制（仅安卓实现，FLAG_KEEP_SCREEN_ON，无需任何权限）
/// PC 上调用是空操作，Windows 不受影响
class ScreenKeepOn {
  static const _channel = MethodChannel('tomato/screen');

  static bool get supported => Platform.isAndroid;

  static Future<void> set(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setKeepOn', {'on': on});
    } catch (_) {
      // 通道不可用时静默忽略
    }
  }

  /// 到时震动提醒（波形：三短震动，强提醒）
  static Future<void> vibrate() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('vibrate');
    } catch (_) {
      // 静默忽略
    }
  }
}
