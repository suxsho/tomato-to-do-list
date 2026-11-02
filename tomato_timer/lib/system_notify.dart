import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// 系统通知：安卓走通知栏（原生 NotificationManager），Windows 走托盘气泡（Shell_NotifyIcon）
/// 两端的调用都是尽力而为，失败时静默忽略，不影响计时主流程。
class SystemNotify {
  static const _channel = MethodChannel('tomato/notify');

  /// 安卓 13+ 需要在运行时申请通知权限；其它平台直接返回
  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  /// 弹一条到时通知
  static Future<void> show({required String title, required String body}) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('notify', {'title': title, 'body': body});
      } catch (_) {}
      return;
    }
    if (Platform.isWindows) {
      _windowToast(title: title, body: body);
    }
  }

  // ---------------- Windows 托盘气泡 ----------------

  /// 记录已添加的托盘图标，用于后续 MODIFY / DELETE
  static bool _iconAdded = false;
  static Timer? _cleanupTimer;
  /// 本次气泡使用的图标句柄（用完需 DestroyIcon，否则泄漏 GDI 对象）
  static int _iconHandle = 0;

  static void _windowToast({required String title, required String body}) {
    try {
      final shell32 = DynamicLibrary.open('shell32.dll');
      final user32 = DynamicLibrary.open('user32.dll');
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      final findWindowW = user32.lookupFunction<
          IntPtr Function(IntPtr, Pointer<Utf16>),
          int Function(int, Pointer<Utf16>)>('FindWindowW');
      final getModuleHandleW = kernel32.lookupFunction<
          IntPtr Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)>('GetModuleHandleW');
      final extractIconW = shell32.lookupFunction<
          IntPtr Function(IntPtr, Pointer<Utf16>, Uint32),
          int Function(int, Pointer<Utf16>, int)>('ExtractIconW');
      final loadIconW = user32.lookupFunction<
          IntPtr Function(IntPtr, IntPtr),
          int Function(int, int)>('LoadIconW');
      final shellNotifyIconW = shell32.lookupFunction<
          Int32 Function(Uint32, Pointer<NOTIFYICONDATAW>),
          int Function(int, Pointer<NOTIFYICONDATAW>)>('Shell_NotifyIconW');

      final titlePtr = _toUtf16('番茄任务清单');
      final hwnd = findWindowW(0, titlePtr);
      calloc.free(titlePtr);
      if (hwnd == 0) return;

      // 图标优先取 exe 内嵌的应用图标（ExtractIconW 第 0 个），
      // 失败时退回系统默认图标 IDI_APPLICATION(32512)。避免气泡里是空白方块。
      var icon = 0;
      final exePtr = _toUtf16(Platform.resolvedExecutable);
      icon = extractIconW(getModuleHandleW(nullptr), exePtr, 0);
      calloc.free(exePtr);
      if (icon <= 1) {
        icon = loadIconW(0, 32512);
      }
      _iconHandle = icon;

      final data = calloc<NOTIFYICONDATAW>();
      final appName = _toUtf16('番茄任务清单');
      final infoTitle = _toUtf16(title);
      final infoBody = _toUtf16(body.length > 240 ? '${body.substring(0, 240)}…' : body);

      data.ref.cbSize = sizeOf<NOTIFYICONDATAW>();
      data.ref.hWnd = hwnd;
      data.ref.uID = 1;
      data.ref.hIcon = icon;
      // NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_INFO
      data.ref.uFlags = 0x1 | 0x2 | 0x4 | 0x10;
      data.ref.uCallbackMessage = 0x8001; // WM_APP + 1（本应用不处理，仅占位）
      _copyUtf16(data.ref.szTip, appName, 128);
      _copyUtf16(data.ref.szInfo, infoBody, 256);
      _copyUtf16(data.ref.szInfoTitle, infoTitle, 64);
      // NIIF_USER（用自定义图标）| NIIF_LARGE_ICON | NIIF_NOSOUND（铃声由应用自己播）
      data.ref.dwInfoFlags = 0x4 | 0x20 | 0x10;
      data.ref.hBalloonIcon = icon;
      data.ref.uTimeout = 10000;

      const nimAdd = 0;
      const nimModify = 1;
      final ok = shellNotifyIconW(nimAdd, data) != 0 || shellNotifyIconW(nimModify, data) != 0;
      if (ok) _iconAdded = true;

      calloc.free(appName);
      calloc.free(infoTitle);
      calloc.free(infoBody);
      calloc.free(data);

      // 气泡展示完把托盘图标收掉，避免常驻任务栏右下角
      _cleanupTimer?.cancel();
      _cleanupTimer = Timer(const Duration(seconds: 12), () {
        if (_iconAdded) {
          try {
            final d = calloc<NOTIFYICONDATAW>();
            d.ref.cbSize = sizeOf<NOTIFYICONDATAW>();
            d.ref.hWnd = hwnd;
            d.ref.uID = 1;
            shellNotifyIconW(2 /* NIM_DELETE */, d);
            calloc.free(d);
            _iconAdded = false;
          } catch (_) {}
        }
        if (_iconHandle > 1) {
          try {
            user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyIcon')(_iconHandle);
          } catch (_) {}
          _iconHandle = 0;
        }
      });
    } catch (_) {
      // 非 Windows / 调用失败：忽略（任务栏闪烁仍会提醒）
    }
  }

  static void _copyUtf16(Array<Uint16> array, Pointer<Utf16> src, int maxLen) {
    final s = src.cast<Uint16>();
    for (var i = 0; i < maxLen; i++) {
      final code = s[i];
      array[i] = code;
      if (code == 0) break;
    }
  }

  static Pointer<Utf16> _toUtf16(String s) {
    final units = s.codeUnits;
    final ptr = calloc<Uint16>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0;
    return ptr.cast<Utf16>();
  }
}

/// Win32 NOTIFYICONDATAW（x64 布局，与 C 头文件字段顺序/对齐一致）
final class NOTIFYICONDATAW extends Struct {
  @Uint32()
  external int cbSize;
  @IntPtr()
  external int hWnd;
  @Uint32()
  external int uID;
  @Uint32()
  external int uFlags;
  @Uint32()
  external int uCallbackMessage;
  @IntPtr()
  external int hIcon;
  @Array(128)
  external Array<Uint16> szTip;
  @Uint32()
  external int dwState;
  @Uint32()
  external int dwStateMask;
  @Array(256)
  external Array<Uint16> szInfo;
  @Uint32()
  external int uTimeout;
  @Array(64)
  external Array<Uint16> szInfoTitle;
  @Uint32()
  external int dwInfoFlags;
  @Array(16)
  external Array<Uint8> guidItem;
  @IntPtr()
  external int hBalloonIcon;
}
