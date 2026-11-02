import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// 安卓系统栏配色：状态栏 / 底部导航条都透明，交给 Flutter 自己绘制背景，
/// 并关闭系统给导航条加的对比度蒙层（否则深色模式下导航条会发白）。
void applySystemUiStyle() {
  if (kIsWeb || !Platform.isAndroid) return;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    statusBarIconBrightness: AppColors.dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: const Color(0x00000000),
    systemNavigationBarDividerColor: const Color(0x00000000),
    systemNavigationBarIconBrightness: AppColors.dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  ));
}

/// 进入沉浸式全屏（防烧屏：连状态栏时钟一起隐藏）
Future<void> enterImmersive() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

/// 退出沉浸式，恢复 edge-to-edge 并重新应用系统栏配色
Future<void> exitImmersive() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  applySystemUiStyle();
}
