import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../system_ui.dart';
import '../theme.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/tomato_view.dart';
import 'focus_settings_dialog.dart';

String fmtSec(int s) {
  final m = s ~/ 60, sec = s % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// 当前时间 HH:mm（防烧屏浮层用，顶部状态栏此时已隐藏）
String fmtClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 当前时间 HH:mm:ss（专注页顶部常显）
String fmtClockSec(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// 计时流程界面：专注 / 到时提醒 / 休息 / 下一个番茄开始前
/// 布局按窗口尺寸自适应（不再固定 520 的手机版宽度），到点后番茄图形转绿。
class TimerFlowScreen extends StatefulWidget {
  const TimerFlowScreen({super.key});

  @override
  State<TimerFlowScreen> createState() => _TimerFlowScreenState();
}

class _TimerFlowScreenState extends State<TimerFlowScreen> with TickerProviderStateMixin {
  final _noteCtrl = TextEditingController();
  String _noteKey = '';

  // ---- 顶部按钮自动隐藏（专注中隐藏返回/设置按钮，触屏点击恢复） ----
  bool _chromeVisible = true;
  Timer? _hideTimer;
  static const _chromeHideDelay = Duration(seconds: 3);

  // ---- 防烧屏位置移动（静止 10 秒 → 线性平移一下 → 再静止 10 秒） ----
  double _burnInDy = 0; // 当前纵向偏移
  Timer? _burnInTimer; // 每 10 秒触发一次移动
  Animation<double>? _burnInMove; // 本次移动的插值
  late final AnimationController _moveCtrl; // 单次移动动画（800ms 线性）

  // ---- 安卓防烧屏全屏（沉浸式，隐藏状态栏时钟）----
  bool _immersive = false;

  @override
  void initState() {
    super.initState();
    _moveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _burnInTimer?.cancel();
    _moveCtrl.dispose();
    _noteCtrl.dispose();
    // 离开计时页时务必恢复系统栏，避免带着沉浸式回到主界面
    if (_immersive) {
      _immersive = false;
      unawaited(exitImmersive());
    }
    super.dispose();
  }

  /// 安卓：防烧屏开启时进入沉浸式全屏（隐藏状态栏时钟），退出时恢复 edge-to-edge
  void _setImmersive(bool on) {
    if (_immersive == on) return;
    _immersive = on;
    if (on) {
      unawaited(enterImmersive());
    } else {
      unawaited(exitImmersive());
    }
  }

  /// 防烧屏生命周期：burnIn 激活时每 10 秒移动一次，退出时复位
  void _ensureBurnInTimer(bool burnIn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (burnIn && _burnInTimer == null) {
        _burnInTimer = Timer.periodic(const Duration(seconds: 10), (_) {
          if (!mounted) return;
          // 交替上下平移 44px，线性动画，移完保持不动
          final next = _burnInDy <= 0 ? 22.0 : -22.0;
          _burnInMove = Tween<double>(begin: _burnInDy, end: next)
              .animate(CurvedAnimation(parent: _moveCtrl, curve: Curves.linear));
          _burnInDy = next;
          _moveCtrl.forward(from: 0);
        });
      } else if (!burnIn && _burnInTimer != null) {
        _burnInTimer?.cancel();
        _burnInTimer = null;
        _burnInMove = null;
        _burnInDy = 0;
      }
    });
  }

  /// 专注计时进行中（未暂停、未到时）才执行自动隐藏
  bool _isFocusRunning(Session s) => s.phase == SessionPhase.focus && !s.isPaused && !s.ended;

  /// 点击屏幕任意处：恢复顶部按钮并重新安排隐藏
  void _onBodyTap() {
    final s = context.read<AppState>().session;
    if (s == null || !_isFocusRunning(s)) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_chromeVisible) setState(() => _chromeVisible = true);
  }

  /// 自动隐藏生命周期：跟随 build 每秒刷新校正（暂停/到时/离开专注时强制恢复显示）
  void _ensureChromeLifecycle(bool autoHide) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (autoHide && _chromeVisible && _hideTimer == null) {
        _hideTimer = Timer(_chromeHideDelay, () {
          _hideTimer = null;
          if (mounted) setState(() => _chromeVisible = false);
        });
      } else if (!autoHide && (!_chromeVisible || _hideTimer != null)) {
        _hideTimer?.cancel();
        _hideTimer = null;
        if (!_chromeVisible) setState(() => _chromeVisible = true);
      }
    });
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
    final focusEnded = isFocus && s.ended; // 番茄到点：图形转绿、提示更明显
    final bg = isBreak ? AppColors.breakBg : AppColors.focusBg;
    final accent = (isBreak || focusEnded) ? AppColors.green : AppColors.red;
    final paused = s.isPaused;
    // Windows 自定义标题栏高 40，到点浮层不盖它，关闭/最小化/置顶仍可点
    final titleBarH = Platform.isWindows ? 40.0 : 0.0;

    // 顶部按钮自动隐藏 / 防烧屏状态
    final autoHide = _isFocusRunning(s);
    final chromeShown = _chromeVisible || !autoHide;
    final burnIn = isFocus && !paused && !s.ended && app.settings.burnInProtectOn && !_chromeVisible;
    _ensureChromeLifecycle(autoHide);
    _ensureBurnInTimer(burnIn);
    _setImmersive(burnIn);

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
        : focusEnded
            ? ('已完成', AppColors.greenLight, AppColors.green, AppColors.green)
            : isFocus
                ? ('专注中', AppColors.redLight, AppColors.red, AppColors.red)
                : isBreak
                    ? (s.phase == SessionPhase.shortBreak ? '短休息' : '长休息', AppColors.greenLight, AppColors.green, AppColors.green)
                    : ('休息结束', AppColors.greenLight, AppColors.green, AppColors.green);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Column(
            children: [
              const AppTitleBar(),
              Expanded(
                child: SafeArea(
                  top: false,
                  // 整页响应式：内容宽度、圆圈、字号都跟着窗口走
                  child: LayoutBuilder(
                    builder: (ctx, outer) {
                      final W = outer.maxWidth;
                      final H = outer.maxHeight;
                      // ---- 整页等比缩放 ----
                      // 设计版面按 820×780 的参考尺寸画，再整体缩放到当前窗口：
                      // 宽高都不够时一起缩，够大时一起放大（上限 1.3，别把圆圈撑爆），
                      // 这样无论窗口被拉成多扁，整页都能完整塞进去，不需要下滑。
                      final sideGap = W >= 720 ? 48.0 : 16.0;
                      final usableW = math.max(W - sideGap, 240.0);
                      // 用户在设置里调过字体大小（1.15 倍等）时文字会变高，先预留这部分高度
                      final ts = MediaQuery.textScalerOf(context).scale(1.0);
                      final needH = 780.0 + 220.0 * (ts - 1.0);
                      final sc = math.min(usableW / 820.0, H / needH).clamp(0.55, 1.30).toDouble();
                      double sz(double v) => v * sc; // 设计稿尺寸 → 当前窗口尺寸
                      final contentW = math.min(usableW, 980.0);
                      final circleSize = sz(300);
                      final timeSize = sz(72);
                      // 备注 / 按钮最多 560 宽并居中，宽屏下不会拉成长条
                      final formW = math.min(contentW, sz(560));
                      return Center(
                        child: SizedBox(
                          width: contentW,
                          height: H,
                          child: Stack(
                            children: [
                              // 全屏点击捕获（透明）：空白处点击也能恢复被隐藏的顶部按钮
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: _onBodyTap,
                                ),
                              ),
                              // 内容区：窗口较矮时整体可滚动，够高时垂直居中
                              SingleChildScrollView(
                                padding: EdgeInsets.zero,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: H),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _onBodyTap,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // 当前时间（常显，专注中显示在状态徽章上方）
                                        Padding(
                                          padding: EdgeInsets.only(bottom: sz(6)),
                                          child: Text(fmtClockSec(DateTime.now()),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize: sz(17),
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textMid,
                                                  letterSpacing: sz(1.5))),
                                        ),
                                        // 顶栏：返回 / 阶段徽章 / 专注设置
                                        // 页内 mini 入口已移除（窗口标题栏上还有），三段严格左右对称
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: sz(16), vertical: sz(10)),
                                          child: Row(
                                            children: [
                                              Visibility(
                                                visible: chromeShown,
                                                maintainSize: true,
                                                maintainAnimation: true,
                                                maintainState: true,
                                                child: _circleBtn(sc: sc, icon: Icons.chevron_left, onTap: () => _onBack(context, app, s)),
                                              ),
                                              Expanded(
                                                child: Center(
                                                  child: Container(
                                                    padding: EdgeInsets.symmetric(horizontal: sz(16), vertical: sz(6)),
                                                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(sz(20))),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Container(
                                                          width: sz(7),
                                                          height: sz(7),
                                                          decoration: BoxDecoration(color: badgeDot, shape: BoxShape.circle),
                                                        ),
                                                        SizedBox(width: sz(6)),
                                                        Text(badgeText,
                                                            style: TextStyle(color: badgeFg, fontSize: sz(13), fontWeight: FontWeight.w800)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Visibility(
                                                visible: chromeShown,
                                                maintainSize: true,
                                                maintainAnimation: true,
                                                maintainState: true,
                                                child: _circleBtn(
                                                  sc: sc,
                                                  icon: Icons.tune,
                                                  onTap: () {
                                                    // 先收起备注输入框的焦点，否则关闭弹窗后键盘会重新弹出
                                                    FocusManager.instance.primaryFocus?.unfocus();
                                                    showFocusSettingsDialog(context);
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // 水波纹计时 + 数字
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isPreStart)
                                              TomatoView(full: true, size: circleSize)
                                            else
                                              WaveTimerView(
                                                progress: waveProgress,
                                                resting: isBreak,
                                                paused: paused,
                                                finished: focusEnded,
                                                size: circleSize,
                                              ),
                                            SizedBox(height: sz(26)),
                                            Text(timeText,
                                                style: TextStyle(
                                                  fontSize: timeSize,
                                                  fontWeight: FontWeight.w900,
                                                  color: paused ? AppColors.textGray : AppColors.textDark,
                                                  letterSpacing: -1,
                                                )),
                                            SizedBox(height: sz(6)),
                                            Text(
                                              isFocus
                                                  ? '本次第 ${s.pomodoroNo} 个番茄 · 专注任务中'
                                                  : isBreak
                                                      ? '休息也是一个番茄的一环'
                                                      : '下一个：专注 ${app.focusDurationMin} 分钟 · 第 ${s.pomodoroNo + 1} 个番茄',
                                              style: TextStyle(
                                                  color: AppColors.textGray,
                                                  fontSize: sz(14),
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            // 当前任务名
                                            if (s.taskName.isNotEmpty) ...[
                                              SizedBox(height: sz(6)),
                                              Text(s.taskName,
                                                  style: TextStyle(
                                                      color: AppColors.textDark,
                                                      fontSize: sz(17),
                                                      fontWeight: FontWeight.w800),
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center),
                                            ],
                                          ],
                                        ),
                                        // 周期圆点 + 任务进度
                                        // 有任务：圆点数量跟随预估番茄数；无预估模式则只显示已完成数
                                        Padding(
                                          padding: EdgeInsets.only(top: sz(12)),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              ...() {
                                                final t = app.currentTask;
                                                if (t != null) {
                                                  final noEst = app.settings.noEstimate || t.estimated <= 0;
                                                  final total = noEst
                                                      ? t.completed
                                                      : math.max(t.estimated, t.completed).clamp(1, 24).toInt();
                                                  return List.generate(total, (i) {
                                                    final filled = i < t.completed;
                                                    return Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: sz(3)),
                                                      child: Icon(Icons.circle, size: sz(12), color: filled ? accent : AppColors.slate300),
                                                    );
                                                  });
                                                }
                                                return List.generate(app.settings.longBreakEvery, (i) {
                                                  final filled = i < app.cycleProgress;
                                                  return Padding(
                                                    padding: EdgeInsets.symmetric(horizontal: sz(3)),
                                                    child: Icon(Icons.circle, size: sz(12), color: filled ? accent : AppColors.slate300),
                                                  );
                                                });
                                              }(),
                                              SizedBox(width: sz(8)),
                                              Builder(builder: (_) {
                                                final t = app.currentTask;
                                                final noEst = t != null && (app.settings.noEstimate || t.estimated <= 0);
                                                return Text(
                                                  t == null
                                                      ? '每 ${app.settings.longBreakEvery} 个番茄后长休息'
                                                      : noEst
                                                          ? '${t.name} · 已完成 ${t.completed} 个'
                                                          : '${t.name} · 已完成 ${t.completed}/${t.estimated} 个',
                                                  style: TextStyle(
                                                      fontSize: sz(12),
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.textGray),
                                                  overflow: TextOverflow.ellipsis,
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: sz(14)),
                                        // 备注卡片（限宽居中）
                                        Center(
                                          child: SizedBox(
                                            width: formW,
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(horizontal: sz(16)),
                                              child: Container(
                                                padding: EdgeInsets.symmetric(horizontal: sz(14)),
                                                decoration: BoxDecoration(
                                                  // 夜间模式用深色实底，避免"白 80% 透明 + 灰字"看不清
                                                  color: AppColors.dark ? AppColors.inputFill : Colors.white.withValues(alpha: 0.8),
                                                  borderRadius: BorderRadius.circular(sz(16)),
                                                  border: Border.all(color: AppColors.cardBorder),
                                                ),
                                                child: TextField(
                                                  controller: _noteCtrl,
                                                  onChanged: app.updateNote,
                                                  style: TextStyle(
                                                      fontSize: sz(14),
                                                      fontWeight: FontWeight.w500,
                                                      color: AppColors.textDark),
                                                  decoration: InputDecoration(
                                                    hintText: '本次专注备注（例如：完成方案第一章）',
                                                    hintStyle: TextStyle(
                                                      color: AppColors.dark ? AppColors.textMid : AppColors.textGray,
                                                      fontSize: sz(14),
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    border: InputBorder.none,
                                                    isDense: true,
                                                    contentPadding: EdgeInsets.symmetric(vertical: sz(12)),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: sz(12)),
                                        // 底部按钮（限宽居中）
                                        Center(
                                          child: SizedBox(
                                            width: formW,
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(horizontal: sz(16)),
                                              child: Row(
                                                children: [
                                                  if (isFocus) ...[
                                                    _bigButton(sc: sc, label: '结束', bg: AppColors.slate100, fg: AppColors.textDark, flex: 1, onTap: () => _confirmEnd(context, app, s)),
                                                    SizedBox(width: sz(12)),
                                                    paused
                                                        ? _bigButton(sc: sc, label: '继续专注', bg: AppColors.amber, fg: Colors.white, flex: 2, onTap: app.togglePause, shadow: const Color(0x55F59E0B))
                                                        : _bigButton(sc: sc, label: '暂停', bg: accent, fg: Colors.white, flex: 2, onTap: app.togglePause),
                                                  ] else if (isBreak) ...[
                                                    _bigButton(sc: sc, label: '跳过休息', bg: AppColors.greenLight, fg: AppColors.textDark, flex: 1, onTap: app.skipBreak),
                                                    SizedBox(width: sz(12)),
                                                    paused
                                                        ? _bigButton(sc: sc, label: '继续休息', bg: AppColors.amber, fg: Colors.white, flex: 2, onTap: app.togglePause, shadow: const Color(0x55F59E0B))
                                                        : _bigButton(sc: sc, label: '暂停', bg: accent, fg: Colors.white, flex: 2, onTap: app.togglePause),
                                                  ] else ...[
                                                    _bigButton(sc: sc, label: '结束专注', bg: AppColors.slate100, fg: AppColors.textDark, flex: 1, onTap: () { app.quitSession(); if (context.mounted) Navigator.of(context).pop(); }),
                                                    SizedBox(width: sz(12)),
                                                    _bigButton(sc: sc, label: '开始下一个番茄', bg: accent, fg: Colors.white, flex: 2, onTap: app.startNextPomodoro),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: sz(16)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          // 到点提醒浮层：遮罩覆盖标题栏以下的整个窗口；卡片尺寸随窗口自适应
          if (isFocus && s.ended)
            Positioned.fill(
              top: titleBarH,
              child: ColoredBox(
                color: const Color(0x61000000),
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    final cardW = math.min(c.maxWidth - 32, 520.0).clamp(280.0, 520.0).toDouble();
                    final hPad = (cardW * 0.08).clamp(20.0, 40.0).toDouble();
                    final vPad = (cardW * 0.08).clamp(26.0, 44.0).toDouble();
                    final titleSize = (cardW * 0.062).clamp(22.0, 32.0).toDouble();
                    final numSize = (cardW * 0.11).clamp(38.0, 58.0).toDouble();
                    final iconBox = (cardW * 0.14).clamp(48.0, 68.0).toDouble();
                    final iconSize = (cardW * 0.08).clamp(28.0, 38.0).toDouble();
                    final subSize = (cardW * 0.032).clamp(12.0, 15.0).toDouble();
                    final btnPad = (cardW * 0.035).clamp(13.0, 18.0).toDouble();
                    final btnSize = (cardW * 0.04).clamp(15.0, 20.0).toDouble();
                    return Center(
                      child: SingleChildScrollView(
                        child: SoftCard(
                          margin: EdgeInsets.zero,
                          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
                          child: SizedBox(
                            width: cardW - hPad * 2,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: iconBox,
                                  height: iconBox,
                                  decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(20)),
                                  // 用已在项目中使用过的 Icons.check，避免新增图标被字体裁剪产物漏掉
                                  child: Icon(Icons.check, color: AppColors.green, size: iconSize),
                                ),
                                const SizedBox(height: 14),
                                Text('番茄时间已结束',
                                    style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                                const SizedBox(height: 6),
                                Text('这一轮完成啦，起来活动一下吧',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: subSize, fontWeight: FontWeight.w600, color: AppColors.textGray)),
                                const SizedBox(height: 16),
                                Text('- ${fmtSec(app.overtimeSec)}',
                                    style: TextStyle(fontSize: numSize, fontWeight: FontWeight.w900, color: AppColors.green)),
                                const SizedBox(height: 22),
                                GestureDetector(
                                  onTap: app.startBreak,
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(vertical: btnPad),
                                    decoration: BoxDecoration(
                                      color: AppColors.green,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: const [BoxShadow(color: Color(0x294EBA8E), blurRadius: 12, offset: Offset(0, 4))],
                                    ),
                                    child: Text('开始休息',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white, fontSize: btnSize, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // 误开计时（忘记关闭）时的出口：不计入任何统计
                                GestureDetector(
                                  onTap: () => _confirmDiscard(context, app),
                                  behavior: HitTestBehavior.opaque,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    child: Text('误开的计时？丢弃这个番茄',
                                        style: TextStyle(
                                            fontSize: subSize,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textGray)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          // 防烧屏黑屏浮层：纯黑背景（无视夜间模式），仅保留倒计时，
          // 内容每 10 秒上下线性平移；点击屏幕恢复正常界面。挂最外层保证最大化时全窗覆盖。
          if (burnIn)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _hideTimer?.cancel();
                  _hideTimer = null;
                  setState(() => _chromeVisible = true);
                },
                child: Container(
                  color: Colors.black,
                  child: AnimatedBuilder(
                    animation: _moveCtrl,
                    builder: (ctx, _) {
                      final dy = _burnInMove?.value ?? _burnInDy;
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 当前时间：只在防烧屏浮层里显示，顶部系统栏此时已隐藏
                              Text(
                                fmtClock(DateTime.now()),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0x99FFFFFF),
                                  letterSpacing: 3,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(timeText,
                                  style: const TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -1,
                                  )),
                              const SizedBox(height: 12),
                              Text(
                                s.taskName.isNotEmpty ? s.taskName : '专注中 · 第 ${s.pomodoroNo} 个番茄',
                                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 28),
                              const Text('点击屏幕显示操作',
                                  style: TextStyle(color: Color(0x55FFFFFF), fontSize: 11, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _circleBtn({required double sc, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36 * sc,
        height: 36 * sc,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Icon(icon, size: 18 * sc, color: AppColors.textMid),
      ),
    );
  }

  Widget _bigButton({required double sc, required String label, required Color bg, required Color fg, required int flex, required VoidCallback onTap, Color? shadow}) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 15 * sc),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16 * sc),
            boxShadow: shadow != null ? [BoxShadow(color: shadow, blurRadius: 10, offset: const Offset(0, 3))] : null,
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 13 * sc, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _onBack(BuildContext context, AppState app, Session s) {
    // 专注中直接返回：计时按时间戳继续，不弹确认（主界面可点"进行中的番茄"回来）
    Navigator.of(context).pop();
  }

  /// 到点浮层里的“丢弃这个番茄”：误开计时时把本次番茄整体作废
  void _confirmDiscard(BuildContext context, AppState app) {
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
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.restore_from_trash_outlined, color: AppColors.textMid, size: 26),
              ),
              const SizedBox(height: 12),
              Text('丢弃这个番茄？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 8),
              Text(
                '本次番茄不计入统计，任务进度和周期计数会一并回退。\n适合计时一直开着、人其实已经离开的情况。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMid, height: 1.6),
              ),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  app.discardPomodoro();
                  if (app.session == null && context.mounted) Navigator.of(context).pop();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x66FF5A5F), blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: const Text('丢弃并退出', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                  child: Text('还是保留', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              // 记录一个番茄（未到时：记录后继续进入休息，留在计时页）
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  app.finishEarly(record: true);
                  // 已自然到时的情况下记录 = 结束会话，退回主界面
                  if (app.session == null && context.mounted) Navigator.of(context).pop();
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
