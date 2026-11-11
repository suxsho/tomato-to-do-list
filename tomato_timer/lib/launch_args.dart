import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 读取进程原始命令行（Windows）。
///
/// Flutter Windows runner 不会把额外参数转成 Dart 的入口参数，所以直接读
/// GetCommandLineW。用途：给 exe 建一个带 `--mini` 的桌面快捷方式，
/// 启动时直接变成桌面小组件。
class LaunchArgs {
  static bool contains(String flag) {
    if (!Platform.isWindows) return false;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getCommandLineW = kernel32.lookupFunction<
          Pointer<Utf16> Function(), Pointer<Utf16> Function()>('GetCommandLineW');
      final ptr = getCommandLineW().cast<Uint16>();
      final buf = StringBuffer();
      for (var i = 0; i < 32768; i++) {
        final unit = ptr[i];
        if (unit == 0) break;
        buf.writeCharCode(unit);
      }
      return buf.toString().contains(flag);
    } catch (_) {
      return false;
    }
  }
}
