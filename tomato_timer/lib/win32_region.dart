import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Win32 窗口形状裁剪（仅 Windows 生效，其它平台全部空操作）。
///
/// 为什么需要它：透明窗口只能让"看不见"，但窗口的四角仍然会接收鼠标点击，
/// 会挡住桌面图标。用 SetWindowRgn 把窗口真正裁成椭圆后，圆外的点击会
/// 直接落到桌面；同时即使某些 Windows 版本上 DWM 透明失效，窗口也不会
/// 露出方形黑底 —— 形状由系统保证，视觉由 Flutter 负责。
final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

class Win32Region {
  static const _windowTitle = '番茄任务清单';

  static int _windowHandle() {
    final user32 = DynamicLibrary.open('user32.dll');
    final findWindowW = user32.lookupFunction<
        IntPtr Function(IntPtr, Pointer<Utf16>),
        int Function(int, Pointer<Utf16>)>('FindWindowW');
    final title = _toUtf16(_windowTitle);
    final handle = findWindowW(0, title);
    calloc.free(title);
    return handle;
  }

  /// 将当前主窗口的客户区裁成椭圆（与方形窗口内切）。
  /// HRGN 交给系统托管，调用后不要再 DeleteObject。
  static void applyCircle() {
    if (!Platform.isWindows) return;
    try {
      final hwnd = _windowHandle();
      if (hwnd == 0) return;

      final user32 = DynamicLibrary.open('user32.dll');
      final gdi32 = DynamicLibrary.open('gdi32.dll');
      final getClientRect = user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<_Rect>),
          int Function(int, Pointer<_Rect>)>('GetClientRect');
      final createEllipticRgn = gdi32.lookupFunction<
          IntPtr Function(Int32, Int32, Int32, Int32),
          int Function(int, int, int, int)>('CreateEllipticRgn');
      final setWindowRgn = user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Int32),
          int Function(int, int, int)>('SetWindowRgn');

      final rect = calloc<_Rect>();
      final ok = getClientRect(hwnd, rect);
      final w = ok == 0 ? 0 : rect.ref.right - rect.ref.left;
      final h = ok == 0 ? 0 : rect.ref.bottom - rect.ref.top;
      calloc.free(rect);
      if (w <= 0 || h <= 0) return;

      // 右下边界为 exclusive，+1 才能把最右/最下一列像素包含进来
      final rgn = createEllipticRgn(0, 0, w + 1, h + 1);
      if (rgn != 0) setWindowRgn(hwnd, rgn, 1);
    } catch (_) {
      // 尽力而为：裁剪失败时仍有透明窗口兜底
    }
  }

  /// 恢复系统默认矩形窗口（旧 HRGN 由系统释放）。
  static void reset() {
    if (!Platform.isWindows) return;
    try {
      final hwnd = _windowHandle();
      if (hwnd == 0) return;
      final user32 = DynamicLibrary.open('user32.dll');
      final setWindowRgn = user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Int32),
          int Function(int, int, int)>('SetWindowRgn');
      setWindowRgn(hwnd, 0, 1);
    } catch (_) {}
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
