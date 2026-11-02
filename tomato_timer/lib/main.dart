import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
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
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(460, 720),
        minimumSize: const Size(360, 560),
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
  runApp(
    ChangeNotifierProvider.value(value: app, child: const TomatoApp()),
  );
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
