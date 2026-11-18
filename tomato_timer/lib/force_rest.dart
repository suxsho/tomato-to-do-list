import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

String _fmt(int s) {
  final m = s ~/ 60, sec = s % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// 强制休息：专注到点后把桌面窗口切成全屏，直到用户点按钮才解除。
///
/// 仅 Windows / Linux 桌面端生效；移动端 / Web 的 [supported] 恒为 false，
/// 所有方法直接空转，设置页也不显示对应开关。
class ForceRest {
  ForceRest._();

  /// 平台是否具备桌面窗口能力
  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// 进入全屏前需要先退出 mini 小窗（由 main 注入，避免循环依赖）
  static Future<void> Function()? beforeEnter;

  static bool _active = false;
  static bool get active => _active;

  static bool? _prevAlwaysOnTop;

  /// 进入全屏。重复调用安全；平台调用失败时静默降级，不影响计时流程。
  static Future<void> enter() async {
    if (!supported || _active) return;
    try {
      if (beforeEnter != null) await beforeEnter!();
      _prevAlwaysOnTop = await windowManager.isAlwaysOnTop();
      await windowManager.setFullScreen(true);
      // 保持置顶，避免被别的窗口盖住而"看起来没生效"
      await windowManager.setAlwaysOnTop(true);
      _active = true;
    } catch (_) {
      _active = false;
    }
  }

  /// 退出全屏并恢复进入前的置顶状态。
  static Future<void> exit() async {
    if (!supported || !_active) return;
    _active = false;
    try {
      await windowManager.setFullScreen(false);
      if (_prevAlwaysOnTop != null) {
        await windowManager.setAlwaysOnTop(_prevAlwaysOnTop!);
        _prevAlwaysOnTop = null;
      }
    } catch (_) {}
  }
}

/// 全局强制休息浮层：挂在 MaterialApp.builder 的 Stack 顶层，
/// 保证用户停在任务 / 统计 / 设置任意页面，到点时都能看到按钮 / 休息倒计时。
///
/// 两个阶段都覆盖全屏：
/// - 专注到点待休息：显示「番茄时间到」卡片，可开始休息 / 丢弃番茄
/// - 休息中（短休/长休）：显示休息倒计时，不提供解除按钮——休息走完自动解除
class ForceRestOverlay extends StatelessWidget {
  const ForceRestOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.session;
    if (!ForceRest.supported || !app.settings.forceRestOn || s == null) {
      return const SizedBox.shrink();
    }
    final isFocusEnded = s.phase == SessionPhase.focus && s.ended;
    final isResting = s.phase == SessionPhase.shortBreak || s.phase == SessionPhase.longBreak;
    if (!isFocusEnded && !isResting) return const SizedBox.shrink();

    return Material(
      color: const Color(0xEE0B1120),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: isResting
                  ? _RestingCard(app: app, long: s.phase == SessionPhase.longBreak)
                  : _FocusEndedCard(app: app),
            ),
          ),
        ),
      ),
    );
  }
}

/// 专注到点、尚未开始休息：给「开始休息」和「丢弃」两个出口。
class _FocusEndedCard extends StatelessWidget {
  final AppState app;
  const _FocusEndedCard({required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 28),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.check, color: AppColors.green, size: 34),
          ),
          const SizedBox(height: 18),
          Text('番茄时间到 · 强制休息',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          const SizedBox(height: 8),
          Text('接下来会全屏强制休息，时间到了自动解除',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textGray)),
          const SizedBox(height: 18),
          Text('- ${_fmt(app.overtimeSec)}',
              style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: AppColors.green)),
          const SizedBox(height: 26),
          GestureDetector(
            onTap: () => app.startBreak(), // 不解除全屏：休息计时走完才自动解除
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x294EBA8E), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: const Text('开始休息',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              unawaited(ForceRest.exit());
              app.discardPomodoro();
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text('误开的计时？丢弃这个番茄',
                  style: TextStyle(fontSize: 12, color: AppColors.textGray, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 休息中：只显示倒计时，不提供解除按钮——强制休息要等休息真正走完才自动解除全屏。
class _RestingCard extends StatelessWidget {
  final AppState app;
  final bool long;
  const _RestingCard({required this.app, required this.long});

  @override
  Widget build(BuildContext context) {
    final remain = app.remainingSec.clamp(0, 1 << 30);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 28),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(20)),
            child: Icon(long ? Icons.self_improvement : Icons.coffee_outlined,
                color: AppColors.green, size: 32),
          ),
          const SizedBox(height: 18),
          Text('强制休息中',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          const SizedBox(height: 8),
          Text(long ? '长休息 · 好好放松一下' : '短休息 · 起来走走，看看远处',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textGray)),
          const SizedBox(height: 20),
          Text(_fmt(remain),
              style: TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: AppColors.green, letterSpacing: 1)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(20)),
            child: Text('休息结束后自动解除全屏',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.green)),
          ),
        ],
      ),
    );
  }
}
