import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// 专注设置二级菜单（计时页右上角按钮弹出，仅快速切换声音/防烧屏等）
/// 弹窗风格与"结束本次番茄？"等界面弹窗一致
/// 震动提醒 / 屏幕常亮仅安卓显示（PC 无对应硬件能力）
Future<void> showFocusSettingsDialog(BuildContext context) {
  // 关键：先收起键盘（备注输入框可能仍有焦点），否则关掉弹窗后键盘会再弹出来
  FocusManager.instance.primaryFocus?.unfocus();
  return showDialog(
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
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            final app = ctx.read<AppState>();
            final s = app.settings;
            final isAndroid = !kIsWeb && Platform.isAndroid;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 图标块
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(16)),
                  child: Center(child: Icon(Icons.tune, size: 28, color: AppColors.red)),
                ),
                const SizedBox(height: 12),
                Text('专注设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                const SizedBox(height: 16),
                // 声音开关
                _toggleRow(
                  icon: s.soundOn ? Icons.volume_up : Icons.volume_off,
                  label: '声音',
                  value: s.soundOn,
                  onChanged: (_) {
                    app.toggleSound();
                    setLocal(() {});
                  },
                ),
                const SizedBox(height: 10),
                // 防烧屏开关
                _toggleRow(
                  icon: Icons.flip_to_back,
                  label: '防烧屏',
                  value: s.burnInProtectOn,
                  onChanged: (_) {
                    app.toggleBurnInProtect();
                    setLocal(() {});
                  },
                ),
                if (isAndroid) ...[
                  const SizedBox(height: 10),
                  // 震动提醒开关（到时三短强震）
                  _toggleRow(
                    icon: s.vibrateOn ? Icons.vibration : Icons.phonelink_erase,
                    label: '震动提醒',
                    value: s.vibrateOn,
                    onChanged: (_) {
                      app.toggleVibrate();
                      setLocal(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  // 屏幕常亮开关（专注时保持屏幕不熄灭）
                  _toggleRow(
                    icon: Icons.brightness_high,
                    label: '屏幕常亮',
                    value: s.keepScreenOn,
                    onChanged: (_) {
                      app.toggleKeepScreenOn();
                      setLocal(() {});
                    },
                  ),
                ],
                const SizedBox(height: 22),
                // 确定
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [BoxShadow(color: Color(0x552563EB), blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: const Text('确定', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

Widget _toggleRow({required IconData icon, required String label, required bool value, required ValueChanged<bool> onChanged}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, size: 18, color: value ? AppColors.red : AppColors.textGray),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark))),
        Switch(value: value, activeTrackColor: AppColors.red, onChanged: onChanged),
      ],
    ),
  );
}
