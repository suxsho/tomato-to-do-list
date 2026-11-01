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
    return MaterialApp(
      title: '番茄任务清单',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.pageBg,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.red, surface: AppColors.pageBg),
        fontFamily: 'Microsoft YaHei',
        useMaterial3: true,
      ),
      home: const MainShell(),
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
              color: Colors.white.withValues(alpha: 0.9),
              border: const Border(top: BorderSide(color: AppColors.slate100)),
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
