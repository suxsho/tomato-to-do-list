import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/mine_screen.dart';
import 'screens/stats_screen.dart';
import 'theme.dart';
import 'widgets/app_title_bar.dart';
import 'widgets/tomato_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  windowManager.waitUntilReadyToShow(
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
            child: IndexedStack(
              index: _index,
              children: const [HomeScreen(), StatsScreen(), MineScreen()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: ClipRect(
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
                    _navItem(2, Icons.person, '我的'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 底部导航 ----------
  Widget _navItem(int i, IconData? icon, String label) {
    final sel = _index == i;
    final iconColor = sel ? AppColors.red : AppColors.textGray;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _index = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon == null
                ? TomatoView(full: true, size: 20, tint: iconColor)
                : Icon(icon, size: 18, color: iconColor),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: iconColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
