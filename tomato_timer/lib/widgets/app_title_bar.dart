import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';

/// 自定义标题栏：拖拽移动 + 双击最大化 + 置顶胶囊 Toggle + 窗口按钮
/// 主界面与计时页共用
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key});

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _pinned = false;
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    final m = await windowManager.isMaximized();
    if (m != _maximized && mounted) setState(() => _maximized = m);
  }

  @override
  void onWindowMaximize() => _refreshMaximized();

  @override
  void onWindowUnmaximize() => _refreshMaximized();

  Future<void> _togglePin() async {
    setState(() => _pinned = !_pinned);
    await windowManager.setAlwaysOnTop(_pinned);
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.barBg,
            border: Border(bottom: BorderSide(color: AppColors.slate100)),
          ),
          child: Row(
            children: [
              // 拖拽移动区域（标题 + 弹性空间）
              Expanded(
                child: GestureDetector(
                  onDoubleTap: _toggleMaximize,
                  child: DragToMoveArea(
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Text('番茄任务清单',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.textDark, letterSpacing: -0.2)),
                      ],
                    ),
                  ),
                ),
              ),
              // 置顶胶囊 Toggle
              GestureDetector(
                onTap: _togglePin,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _pinned ? AppColors.red : AppColors.slate100,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: _pinned ? const [BoxShadow(color: Color(0x33FF5A5F), blurRadius: 6, offset: Offset(0, 2))] : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.push_pin, size: 10, color: _pinned ? Colors.white : AppColors.textGray),
                      const SizedBox(width: 4),
                      Text(_pinned ? '已置顶' : '置顶',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _pinned ? Colors.white : AppColors.textGray)),
                    ],
                  ),
                ),
              ),
              // 窗口控制按钮
              _WinButton(icon: Icons.minimize, onTap: windowManager.minimize),
              _WinButton(
                icon: _maximized ? Icons.filter_none : Icons.crop_square,
                onTap: _toggleMaximize,
                iconScale: _maximized ? 0.7 : 0.85,
              ),
              _WinButton(icon: Icons.close, onTap: windowManager.close, isClose: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标题栏窗口按钮（带悬停效果；关闭键悬停红底）
class _WinButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  final double iconScale;
  const _WinButton({required this.icon, required this.onTap, this.isClose = false, this.iconScale = 1});

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final close = widget.isClose && _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 38,
          height: 40,
          color: close ? const Color(0xFFE81123) : (_hover ? AppColors.slate100 : Colors.transparent),
          child: Icon(
            widget.icon,
            size: 14 * widget.iconScale,
            color: close ? Colors.white : (_hover ? AppColors.textDark : AppColors.textGray),
          ),
        ),
      ),
    );
  }
}
