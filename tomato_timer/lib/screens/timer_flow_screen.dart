import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/tomato_view.dart';

String fmtSec(int s) {
  final m = s ~/ 60, sec = s % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// 计时流程界面：专注 / 到时提醒 / 休息 / 下一个番茄开始前
class TimerFlowScreen extends StatefulWidget {
  const TimerFlowScreen({super.key});

  @override
  State<TimerFlowScreen> createState() => _TimerFlowScreenState();
}

class _TimerFlowScreenState extends State<TimerFlowScreen> {
  final _noteCtrl = TextEditingController();
  String _noteKey = '';

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 新番茄开始时清空备注
  void _syncNote(Session s) {
    final key = '${s.pomodoroNo}';
    if (_noteKey != key) {
      _noteKey = key;
      _noteCtrl.text = s.note;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.session;
    if (s == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    _syncNote(s);

    final isBreak = s.phase == SessionPhase.shortBreak || s.phase == SessionPhase.longBreak;
    final isFocus = s.phase == SessionPhase.focus;
    final isPreStart = s.phase == SessionPhase.preStart;
    final bg = isBreak ? AppColors.breakBg : AppColors.focusBg;
    final accent = isBreak ? AppColors.green : AppColors.red;
    final paused = s.isPaused;

    // 水波纹已进行比例（水位随时间从底部上涨）
    double waveProgress = 0;
    if (isFocus || isBreak) {
      waveProgress = (app.elapsedSec / s.durationSec).clamp(0.0, 1.0);
    }

    final String timeText;
    if (isFocus) {
      timeText = app.remainingSec >= 0 ? fmtSec(app.remainingSec) : '- ${fmtSec(app.overtimeSec)}';
    } else if (isBreak) {
      timeText = fmtSec(app.remainingSec.clamp(0, 1 << 30));
    } else {
      timeText = fmtSec(s.durationSec);
    }

    // 顶部徽章状态
    final (String badgeText, Color badgeBg, Color badgeFg, Color badgeDot) = paused
        ? ('已暂停', AppColors.amberLight, AppColors.amberDark, AppColors.amber)
        : isFocus
            ? ('专注中', AppColors.redLight, AppColors.red, AppColors.red)
            : isBreak
                ? (s.phase == SessionPhase.shortBreak ? '短休息' : '长休息', AppColors.greenLight, AppColors.green, AppColors.green)
                : ('休息结束', AppColors.greenLight, AppColors.green, AppColors.green);

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          const AppTitleBar(),
          Expanded(
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
            child: Stack(
              children: [
                Column(
                  children: [
                    // 顶栏：返回 / 阶段徽章 / 提示音
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          _circleBtn(icon: Icons.chevron_left, onTap: () => _onBack(context, app, s)),
                          Expanded(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(color: badgeDot, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(badgeText, style: TextStyle(color: badgeFg, fontSize: 12, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _circleBtn(
                            icon: app.settings.soundOn ? Icons.volume_up : Icons.volume_off,
                            onTap: app.toggleSound,
                          ),
                        ],
                      ),
                    ),
                    // 水波纹计时 + 数字
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isPreStart)
                              TomatoView(full: true, size: 200)
                            else
                              LayoutBuilder(builder: (ctx, box) {
                                final size = (box.maxHeight < box.maxWidth ? box.maxHeight : box.maxWidth) * 0.85;
                                return WaveTimerView(progress: waveProgress, resting: isBreak, paused: paused, size: size.clamp(160.0, 240.0));
                              }),
                            const SizedBox(height: 20),
                            Text(timeText,
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  color: paused ? AppColors.textGray : AppColors.textDark,
                                  letterSpacing: -1,
                                )),
                            const SizedBox(height: 6),
                            Text(
                              isFocus
                                  ? '本次第 ${s.pomodoroNo} 个番茄 · 专注任务中'
                                  : isBreak
                                      ? '休息也是一个番茄的一环'
                                      : '下一个：专注 ${app.settings.focusMin} 分钟 · 第 ${s.pomodoroNo + 1} 个番茄',
                              style: TextStyle(color: AppColors.textGray, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            // 当前任务名
                            if (s.taskName.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(s.taskName,
                                  style: TextStyle(color: AppColors.textDark, fontSize: 14, fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // 周期圆点 + 任务进度
                    // 有任务：圆点数量跟随任务的预估番茄数（实际超过预估时圆点随之增加）
                    // 无任务：保持"每 N 个番茄长休息"的周期圆点
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ...() {
                          final t = app.currentTask;
                          if (t != null) {
                            final total = math.max(t.estimated, t.completed).clamp(1, 24);
                            return List.generate(total, (i) {
                              final filled = i < t.completed;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: Icon(Icons.circle, size: 10, color: filled ? accent : AppColors.slate300),
                              );
                            });
                          }
                          return List.generate(app.settings.longBreakEvery, (i) {
                            final filled = s.phase == SessionPhase.longBreak || i < s.cycleDone % app.settings.longBreakEvery;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(Icons.circle, size: 10, color: filled ? accent : AppColors.slate300),
                            );
                          });
                        }(),
                        const SizedBox(width: 8),
                        Builder(builder: (_) {
                          final t = app.currentTask;
                          return Text(
                            t == null
                                ? '每 ${app.settings.longBreakEvery} 个番茄后长休息'
                                : '${t.name} · 已完成 ${t.completed}/${t.estimated} 个',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textGray),
                            overflow: TextOverflow.ellipsis,
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // 备注卡片
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: TextField(
                          controller: _noteCtrl,
                          onChanged: app.updateNote,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textDark),
                          decoration: InputDecoration(
                            hintText: '本次专注备注（例如：完成方案第一章）',
                            hintStyle: TextStyle(color: AppColors.textGray, fontSize: 12, fontWeight: FontWeight.w500),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 底部按钮
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          if (isFocus) ...[
                            _bigButton(label: '结束', bg: AppColors.slate100, fg: AppColors.textDark, flex: 1, onTap: () => _confirmEnd(context, app, s)),
                            const SizedBox(width: 12),
                            paused
                                ? _bigButton(label: '继续专注', bg: AppColors.amber, fg: Colors.white, flex: 2, onTap: app.togglePause, shadow: const Color(0x55F59E0B))
                                : _bigButton(label: '暂停', bg: accent, fg: Colors.white, flex: 2, onTap: app.togglePause),
                          ] else if (isBreak) ...[
                            _bigButton(label: '跳过休息', bg: AppColors.greenLight, fg: AppColors.textDark, flex: 1, onTap: app.skipBreak),
                            const SizedBox(width: 12),
                            paused
                                ? _bigButton(label: '继续休息', bg: AppColors.amber, fg: Colors.white, flex: 2, onTap: app.togglePause, shadow: const Color(0x55F59E0B))
                                : _bigButton(label: '暂停', bg: accent, fg: Colors.white, flex: 2, onTap: app.togglePause),
                          ] else ...[
                            _bigButton(label: '结束专注', bg: AppColors.slate100, fg: AppColors.textDark, flex: 1, onTap: () { app.quitSession(); if (context.mounted) Navigator.of(context).pop(); }),
                            const SizedBox(width: 12),
                            _bigButton(label: '开始下一个番茄', bg: accent, fg: Colors.white, flex: 2, onTap: app.startNextPomodoro),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
                // 到时提醒浮层
                if (isFocus && s.ended)
                  Positioned.fill(
                    child: ColoredBox(
                      color: const Color(0x61000000),
                      child: Center(
                        child: SoftCard(
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('番茄时间已结束', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                              const SizedBox(height: 16),
                              Text('- ${fmtSec(app.overtimeSec)}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.red)),
                              const SizedBox(height: 20),
                              GestureDetector(
                                onTap: app.startBreak,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.green,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: const [BoxShadow(color: Color(0x294EBA8E), blurRadius: 10, offset: Offset(0, 3))],
                                  ),
                                  child: const Text('开始休息', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
            ),
          ],
        ),
    );
  }

  Widget _circleBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Icon(icon, size: 18, color: AppColors.textMid),
      ),
    );
  }

  Widget _bigButton({required String label, required Color bg, required Color fg, required int flex, required VoidCallback onTap, Color? shadow}) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: shadow != null ? [BoxShadow(color: shadow, blurRadius: 10, offset: const Offset(0, 3))] : null,
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _onBack(BuildContext context, AppState app, Session s) {
    // 专注中直接返回：计时按时间戳继续，不弹确认（主界面可点"进行中的番茄"回来）
    Navigator.of(context).pop();
  }

  void _confirmEnd(BuildContext context, AppState app, Session s) {
    showDialog(
      context: context,
      barrierColor: const Color(0x660F172A),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.card, // 实色打底，防止渐变透明导致透底
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppColors.modalGradient),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.cardBorder),
                          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 16))],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 番茄图标块
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(16)),
                              child: Center(child: TomatoView(full: true, size: 34)),
                            ),
                            const SizedBox(height: 12),
                            Text('结束本次番茄？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                            const SizedBox(height: 8),
                            Text(
                              '可以选择记录本次番茄（按实际已专注时长），或放弃本次。',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: AppColors.textMid, height: 1.6),
                            ),
              const SizedBox(height: 22),
              // 记录一个番茄
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  app.finishEarly(record: true);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x66FF5A5F), blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: const Text('记录一个番茄', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              // 放弃本次番茄
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  app.finishEarly(record: false);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                  child: Text('放弃本次番茄', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
