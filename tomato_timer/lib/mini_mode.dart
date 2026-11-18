import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets/tomato_view.dart';
import 'win32_region.dart';

/// 秒 -> mm:ss（与计时页保持一致；此处单独定义，避免和计时页形成循环依赖）
String _fmtSec(int s) {
  final m = s ~/ 60;
  final sec = s % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// mini 计时模式：把主窗口"变形"成一个透明、无边框、可置顶的圆形小窗口。
///
/// 设计取舍：不新开第二个 Flutter 窗口（多窗口需要独立 isolate，计时状态
/// 同步成本高），而是同一个窗口切换形态。这样 AppState、导航栈、进行中的
/// 会话全部原样保留，切回来不会丢状态。
class MiniModeController extends ChangeNotifier
    with WindowListener, ScreenListener {
  static const double windowSize = 140;
  static const double circleSize = 124;

  static const _kX = 'mini_win_x';
  static const _kY = 'mini_win_y';
  static const _kPin = 'mini_pin';

  bool mini = false;
  bool pinned = true;

  // Windows / Linux 桌面端都支持迷你小窗。核心能力（无边框、透明、置顶、
  // 拖动）window_manager 在 Linux 上均可用；仅 Win32Region 的圆形裁剪在
  // Linux 上是空操作——圆外那圈透明区域仍会接收点击（视觉是圆的，点击区是方的）。
  bool get supported => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  SharedPreferences? _prefs;
  Rect? _restoreBounds;
  bool _restorePinned = false;
  bool _busy = false;
  Timer? _saveTimer;
  // 运行中屏幕布局可能变（拔插外接屏、改分辨率、切换投影模式），
  // 低频巡检把小窗拉回可见区，不让它留在已经不存在的屏幕坐标上。
  Timer? _guardTimer;
  bool _checking = false;

  Future<void> init() async {
    if (!supported) return;
    _prefs = await SharedPreferences.getInstance();
    pinned = _prefs?.getBool(_kPin) ?? true;
    windowManager.addListener(this);
    screenRetriever.addListener(this);
  }

  Future<void> enter() async {
    if (!supported || mini || _busy) return;
    _busy = true;
    try {
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      _restoreBounds = await windowManager.getBounds();
      _restorePinned = await windowManager.isAlwaysOnTop();

      // 注意：不能调用 setResizable(false)。window_manager 在 Windows 上
      // 会用 WM_NCHITTEST -> HTNOWHERE 实现"不可调整大小"，那会让整个窗口
      // 连点击/拖动都收不到。改用 min/max 把尺寸锁死。
      await windowManager.setMinimumSize(const Size(windowSize, windowSize));
      await windowManager.setMaximumSize(const Size(windowSize, windowSize));
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setSize(const Size(windowSize, windowSize));
      await windowManager.setBackgroundColor(Colors.transparent);

      final x = _prefs?.getDouble(_kX);
      final y = _prefs?.getDouble(_kY);
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      } else {
        await windowManager.setAlignment(Alignment.bottomRight);
        final p = await windowManager.getPosition();
        await windowManager.setPosition(Offset(p.dx - 16, p.dy - 16));
      }
      // 保存的坐标可能来自另一块更宽的屏 / 上一次的多屏布局，换到窄屏后
      // 窗口会整个落到屏幕外（进程还在，只是看不见）。这里统一纠正一次。
      await _ensureVisible();
      await windowManager.setAlwaysOnTop(pinned);

      mini = true;
      notifyListeners();
      _startGuard();

      // 等 native 侧把尺寸/setBounds 落地后再裁剪，否则会裁到旧尺寸
      await Future<void>.delayed(const Duration(milliseconds: 180));
      Win32Region.applyCircle();
    } finally {
      _busy = false;
    }
  }

  Future<void> exit() async {
    if (!supported || !mini || _busy) return;
    _busy = true;
    try {
      _stopGuard();
      await _savePosition();
      Win32Region.reset(); // 必须先解除圆形裁剪，否则放大后主界面会被裁掉
      // Linux 进入 mini 时 setAsFrameless 去掉了系统标题栏，退出时必须恢复，
      // 否则主界面没有标题栏、无法拖动/关闭。Windows 用自绘标题栏，无需处理。
      if (Platform.isLinux) {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      }
      await windowManager.setBackgroundColor(AppColors.pageBg);
      // 注意：不能用 Size(-1,-1) 解除上限 —— Windows 端 SetMaximumSize 只在
      // width/height >= 0 时写入，传负数会被静默忽略，窗口会一直卡在 140x140。
      await windowManager.setMaximumSize(const Size(10000, 10000));
      await windowManager.setMinimumSize(const Size(380, 520));
      await windowManager.setAlwaysOnTop(_restorePinned);
      if (_restoreBounds != null) {
        await windowManager.setBounds(_restoreBounds);
      } else {
        await windowManager.setSize(const Size(1120, 720));
        await windowManager.setAlignment(Alignment.center);
      }
      await windowManager.setHasShadow(true);
      mini = false;
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  Future<void> toggle() async => mini ? exit() : enter();

  Future<void> togglePin() async {
    pinned = !pinned;
    notifyListeners();
    await _prefs?.setBool(_kPin, pinned);
    if (mini && supported) await windowManager.setAlwaysOnTop(pinned);
  }

  Future<void> _savePosition() async {
    if (!mini || !supported) return;
    final p = await windowManager.getPosition();
    await _prefs?.setDouble(_kX, p.dx);
    await _prefs?.setDouble(_kY, p.dy);
  }

  void _startGuard() {
    _guardTimer?.cancel();
    _guardTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mini) _ensureVisible();
    });
  }

  void _stopGuard() {
    _guardTimer?.cancel();
    _guardTimer = null;
  }

  /// 把小窗约束到当前屏幕的可见工作区内。
  ///
  /// 单位说明：window_manager 的 get/setPosition 与 screen_retriever 的
  /// visiblePosition / visibleSize 都是逻辑像素（原生侧已按显示器 DPI 换算），
  /// 可以直接比较，不需要再乘除 devicePixelRatio。
  ///
  /// 归属屏取「与窗口重叠最多」的那块；完全在屏外时取离窗口中心最近的一块。
  /// 然后只 clamp 左上角，这样原来贴右下角的小窗换到窄屏后仍贴右下角。
  Future<void> _ensureVisible() async {
    if (!supported || _checking) return;
    _checking = true;
    try {
      // 巡检是「尽力而为」：拿不到屏幕信息或平台调用异常时都不动窗口，
      // 也不把异常抛给定时器回调。
      final displays = await screenRetriever.getAllDisplays();
      if (displays.isEmpty) return;

      final p = await windowManager.getPosition();
      final win = Rect.fromLTWH(p.dx, p.dy, windowSize, windowSize);
      final areas = displays.map((d) {
        final size = d.visibleSize ?? d.size;
        final origin = d.visiblePosition ?? Offset.zero;
        return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
      }).toList();

      var target = areas.first;
      var bestOverlap = -1.0;
      for (final a in areas) {
        final w = math.min(win.right, a.right) - math.max(win.left, a.left);
        final h = math.min(win.bottom, a.bottom) - math.max(win.top, a.top);
        final overlap = (w > 0 && h > 0) ? w * h : 0.0;
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          target = a;
        }
      }
      // 完全落在所有屏幕之外：改选离窗口中心最近的一块屏
      if (bestOverlap <= 0) {
        final c = win.center;
        var bestDist = double.infinity;
        for (final a in areas) {
          final dx = math.max(a.left - c.dx, math.max(0.0, c.dx - a.right));
          final dy = math.max(a.top - c.dy, math.max(0.0, c.dy - a.bottom));
          final dist = dx * dx + dy * dy;
          if (dist < bestDist) {
            bestDist = dist;
            target = a;
          }
        }
      }

      const margin = 12.0;
      double clamp(double v, double lo, double hi) =>
          hi < lo ? lo : v.clamp(lo, hi).toDouble();
      final nx = clamp(
          p.dx, target.left + margin, target.right - windowSize - margin);
      final ny = clamp(
          p.dy, target.top + margin, target.bottom - windowSize - margin);
      if ((nx - p.dx).abs() > 0.5 || (ny - p.dy).abs() > 0.5) {
        await windowManager.setPosition(Offset(nx, ny));
        // 立即落盘，不能只靠 onWindowMove：enter() 期间 mini 还是 false 会被
        // 守卫挡掉，且程序触发的移动事件也不保证送达。下次启动（含 --mini）
        // 直接落在正确位置。
        await _prefs?.setDouble(_kX, nx);
        await _prefs?.setDouble(_kY, ny);
      }
    } catch (_) {
      // 屏幕信息不可用 / 平台调用失败：保持现状，等下一次巡检再试
    } finally {
      _checking = false;
    }
  }

  @override
  void onScreenEvent(String eventName) {
    // 插拔外接屏时立即纠正，不必等下一次巡检
    if (mini) _ensureVisible();
  }

  @override
  void onWindowMove() {
    if (!mini) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _savePosition);
  }

  @override
  void onWindowMoved() => onWindowMove();

  @override
  void onWindowResize() {
    // 跨不同 DPI 显示器移动时客户区像素尺寸会变，重新裁一次
    if (mini) Win32Region.applyCircle();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _stopGuard();
    if (supported) {
      windowManager.removeListener(this);
      screenRetriever.removeListener(this);
    }
    super.dispose();
  }
}

/// 圆形小组件本体：粉色波浪圆环 + 圈内倒计时。
/// 拖动能移动窗口，双击回完整界面，右键弹出设置菜单。
class MiniTimerView extends StatefulWidget {
  const MiniTimerView({super.key});

  @override
  State<MiniTimerView> createState() => _MiniTimerViewState();
}

class _MiniTimerViewState extends State<MiniTimerView> with WindowListener {
  bool _menuOpen = false;
  static const _ink = Color(0xFF2D3748);
  static const _inkSub = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// 点到别的窗口时自动收起菜单，和原生右键菜单行为一致
  @override
  void onWindowBlur() => _setMenu(false);

  /// 菜单展开时临时解除椭圆裁剪，否则菜单卡片的四角会被窗口 region 削掉；
  /// 收起后恢复圆形，圆外的点击继续穿透到桌面。
  void _setMenu(bool open) {
    if (_menuOpen == open) return;
    _menuOpen = open;
    if (mounted) setState(() {});
    if (open) {
      Win32Region.reset();
    } else {
      Win32Region.applyCircle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ctl = context.watch<MiniModeController>();
    final s = app.session;

    final isBreak = s != null &&
        (s.phase == SessionPhase.shortBreak || s.phase == SessionPhase.longBreak);
    final isFocus = s?.phase == SessionPhase.focus;
    final paused = s?.isPaused ?? false;
    // 番茄到点：圆形小组件同样整圆变绿，提示"这一轮完成了"
    final finished = isFocus && (s?.ended ?? false);

    // 休息结束后的等待态（preStart）：不计水位，否则起点被重置后波浪会从 0 慢慢涨满
    final progress = (s == null || s.phase == SessionPhase.preStart)
        ? 0.0
        : (app.elapsedSec / s.durationSec).clamp(0.0, 1.0);
    final String timeText;
    final String label;
    if (s == null) {
      timeText = _fmtSec(app.settings.focusMin * 60);
      label = '未开始';
    } else if (isFocus) {
      timeText = app.remainingSec >= 0
          ? _fmtSec(app.remainingSec)
          : '- ${_fmtSec(app.overtimeSec)}';
      label = paused ? '已暂停' : (finished ? '已完成' : '专注中');
    } else if (isBreak) {
      timeText = _fmtSec(app.remainingSec.clamp(0, 1 << 30));
      label = paused
          ? '已暂停'
          : (s.phase == SessionPhase.longBreak ? '长休息' : '短休息');
    } else {
      timeText = _fmtSec(s.durationSec);
      label = '休息结束';
    }

    // 水位涨到标签所在高度后改用白字，避免在红色波浪上看不清
    final labelColor = progress > 0.45 ? const Color(0xE6FFFFFF) : _inkSub;
    final timeColor = finished ? const Color(0xFF2E9E76) : _ink;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapUp: (_) => _setMenu(!_menuOpen),
          onTap: () {
            if (_menuOpen) _setMenu(false);
          },
          // 菜单打开时撤掉双击识别，否则所有菜单项点击都要等双击判定超时
          onDoubleTap: _menuOpen ? null : () => ctl.exit(),
          // 不用 window_manager 的 DragToMoveArea：它内部注册了 onDoubleTap（最大化），
          // 会抢走我们的双击退出。这里只取它的拖动能力。
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              if (!_menuOpen) windowManager.startDragging();
            },
            child: Center(
              child: SizedBox(
                width: MiniModeController.circleSize,
                height: MiniModeController.circleSize,
                child: Stack(
                  children: [
                    WaveTimerView(
                      progress: progress,
                      resting: isBreak,
                      paused: paused,
                      finished: finished,
                      size: MiniModeController.circleSize,
                      forceLight: true,
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeText,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: timeColor,
                              letterSpacing: 0.3,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: labelColor,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_menuOpen) _buildMenu(context, app, ctl, s),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, AppState app, MiniModeController ctl, Session? s) {
    void close() => _setMenu(false);

    return Positioned.fill(
      child: Center(
        child: Container(
          width: 118,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            // 不用外阴影：窗口被裁成圆形，扩散的阴影会在圆外留下一圈灰色裁切痕迹
            border: Border.all(color: const Color(0xFFEEF0F4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _item(
                icon: Icons.push_pin,
                label: ctl.pinned ? '取消置顶' : '窗口置顶',
                active: ctl.pinned,
                onTap: () {
                  ctl.togglePin();
                  close();
                },
              ),
              if (s != null && !s.ended)
                _item(
                  icon: s.isPaused ? Icons.play_arrow : Icons.pause,
                  label: s.isPaused ? '继续计时' : '暂停计时',
                  onTap: () {
                    app.togglePause();
                    close();
                  },
                ),
              _item(
                icon: Icons.open_in_full,
                label: '返回完整界面',
                onTap: () {
                  close();
                  ctl.exit();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: [
              Icon(icon, size: 13, color: active ? AppColors.red : _inkSub),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: active ? AppColors.red : _ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
