import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 任务栏图标闪烁提醒（仅 Windows，FlashWindowEx）
/// 窗口回到前台后系统会自动停止闪烁
void flashTaskbar({String windowTitle = '番茄任务清单'}) {
  if (!Platform.isWindows) return;
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    final findWindowW = user32.lookupFunction<
        IntPtr Function(IntPtr, Pointer<Utf16>),
        int Function(int, Pointer<Utf16>)>('FindWindowW');
    final flashWindowEx = user32.lookupFunction<
        Int32 Function(Pointer<FLASHWINFO>),
        int Function(Pointer<FLASHWINFO>)>('FlashWindowEx');

    // 按窗口标题查找主窗口句柄
    final titlePtr = _toUtf16(windowTitle);
    final hwnd = findWindowW(0, titlePtr);
    calloc.free(titlePtr);
    if (hwnd == 0) return;

    final info = calloc<FLASHWINFO>();
    info.ref.cbSize = sizeOf<FLASHWINFO>();
    info.ref.hwnd = hwnd;
    // FLASHW_ALL(0x3) | FLASHW_TIMERNOFG(0xC)：闪烁直到窗口到前台
    info.ref.dwFlags = 0x3 | 0xC;
    info.ref.uCount = 0;
    info.ref.dwTimeout = 0;
    flashWindowEx(info);
    calloc.free(info);
  } catch (_) {
    // 非 Windows 或调用失败时静默忽略
  }
}

Pointer<Utf16> _toUtf16(String s) {
  final units = s.codeUnits;
  final ptr = calloc<Uint16>(units.length + 1);
  for (var i = 0; i < units.length; i++) {
    ptr[i] = units[i];
  }
  ptr[units.length] = 0;
  return ptr.cast<Utf16>();
}

/// Win32 FLASHWINFO 结构
final class FLASHWINFO extends Struct {
  @Uint32()
  external int cbSize;
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int uCount;
  @Uint32()
  external int dwTimeout;
}
