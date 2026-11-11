import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'launch_args.dart';
import 'mini_mode.dart';
import 'screens/home_screen.dart';
import 'screens/mine_screen.dart';
import 'screens/stats_screen.dart';
import 'system_ui.dart';
import 'theme.dart';
import 'widgets/app_title_bar.dart';
import 'widgets/tomato_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 安卓走 edge-to-edge：状态栏/导航条透明，由 Flutter 负责铺底色
  if (!kIsWeb && Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // 自定义窗口标题栏仅在 Windows 上初始化（安卓上 window_manager 不可用）
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    // 默认横屏打开；小屏幕上按可用工作区收一点，别顶出屏幕
    var winSize = const Size(1120, 720);
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final area = display.visibleSize ?? display.size; // 物理像素
      final dpr = PlatformDispatcher.instance.views.first.devicePixelRatio;
      final logical = Size(area.width / dpr, area.height / dpr);
      winSize = Size(
        math.min(1120, logical.width * 0.92),
        math.min(720, logical.height * 0.92),
      );
    } catch (_) {}
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        // PC 默认横屏打开（左侧导航 + 左右分栏），不再像手机竖屏窗口
        size: winSize,
        minimumSize: const Size(380, 520),
        center: true,
        title: '番茄任务清单',
        titleBarStyle: TitleBarStyle.hidden, // 自定义标题栏
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  final app = AppState();
  await app.init();
  final mini = MiniModeController();
  await mini.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: mini),
      ],
      child: const TomatoApp(),
    ),
  );

  // 桌面快捷方式带 --mini 时，启动后直接变成圆形小组件。
  // 等首帧渲染完再改窗口，避免 native 侧还没准备好就被 setBounds。
  if (!kIsWeb && Platform.isWindows && LaunchArgs.contains('--mini')) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await mini.enter();
    });
  }
}

class TomatoApp extends StatelessWidget {
  const TomatoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // 主题模式：跟随系统（默认）/ 浅色 / 深色；同步 AppColors 运行时深色标志
    final mode = switch (app.settings.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final platformDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    AppColors.dark = mode == ThemeMode.dark || (mode == ThemeMode.system && platformDark);

    // 安卓系统栏跟随主题：状态栏 / 底部导航条透明 + 关闭对比度蒙层
    applySystemUiStyle();

    return MaterialApp(
      title: '番茄任务清单',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: mode,
      home: const MainShell(),
      // 全局字体缩放：设置页「字体大小」在此生效（小 0.9 / 标准 1.0 / 大 1.15）
      // mini 模式：不替换 home，而是把原界面 Offstage 掉再叠一层圆形小窗，
      // 这样导航栈 / 进行中的会话 / 计时页状态全部原样保留。
      builder: (context, child) {
        final isMini = context.watch<MiniModeController>().mini;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(app.settings.fontScale)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(offstage: isMini, child: child!),
              if (isMini) const Positioned.fill(child: MiniTimerView()),
            ],
          ),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.pageBg,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.red, brightness: brightness, surface: AppColors.pageBg),
      fontFamily: 'Microsoft YaHei',
      useMaterial3: true,
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppTitleBar(),
          Expanded(
            // 自适应响应布局：宽>高（横屏 / PC 全屏等）时导航放左侧，竖屏放底部
            child: LayoutBuilder(
              builder: (context, cons) {
                final landscape = cons.maxWidth > cons.maxHeight;
                final pages = IndexedStack(
                  index: _index,
                  children: const [HomeScreen(), StatsScreen(), MineScreen()],
                );
                if (landscape) {
                  return Row(
                    children: [
                      _sideNav(),
                      Container(width: 1, color: AppColors.cardBorder),
                      Expanded(child: pages),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: pages),
                    _bottomNav(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 底部 / 侧边导航 ----------

  /// 竖屏：底部导航栏
  Widget _bottomNav() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.barBg,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  _navItem(0, null, '任务'),
                  _navItem(1, Icons.bar_chart, '统计'),
                  _navItem(2, Icons.settings_outlined, '设置'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 横屏：左侧导航栏
  Widget _sideNav() {
    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: AppColors.barBg,
        border: Border(right: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            _navItem(0, null, '任务', rail: true),
            _navItem(1, Icons.bar_chart, '统计', rail: true),
            _navItem(2, Icons.settings_outlined, '设置', rail: true),
          ],
        ),
      ),
    );
  }

  // ---------- 导航项 ----------
  Widget _navItem(int i, IconData? icon, String label, {bool rail = false}) {
    final sel = _index == i;
    final iconColor = sel ? AppColors.red : AppColors.textGray;
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon == null
            ? TomatoView(full: true, size: 20, tint: iconColor)
            : Icon(icon, size: 18, color: iconColor),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: iconColor, fontWeight: FontWeight.bold)),
      ],
    );
    if (rail) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _index = i),
        child: SizedBox(width: 76, height: 60, child: content),
      );
    }
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _index = i),
        child: content,
      ),
    );
  }
}
