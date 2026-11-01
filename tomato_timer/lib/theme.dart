import 'package:flutter/material.dart';

/// 全局配色（韩系简约风：珊瑚红 + 白卡片 + 浅灰底 + 休息绿）
class AppColors {
  static const pageBg = Color(0xFFF6F8FA); // 页面浅灰底
  static const card = Colors.white; // 卡片白
  static const cardBorder = Color(0x80F0F2F5); // 卡片描边

  static const red = Color(0xFFFF5A5F); // 主色珊瑚红
  static const redDark = Color(0xFFE0484D); // 按压态深红
  static const redLight = Color(0xFFFFE3E3); // 浅红底/徽章底
  static const redBg = Color(0xFFFFF5F5); // 红色浅背景
  static const headerBg = Color(0xFFFFF7F7); // 头部卡片渐变起色

  static const green = Color(0xFF4EBA8E); // 休息绿
  static const greenDark = Color(0xFF3DA279); // 按压态深绿
  static const greenLight = Color(0xFFD1F2E3); // 浅绿底/徽章底
  static const greenBg = Color(0xFFEAF8F2); // 绿色浅背景
  static const breakBg = Color(0xFFF0FAF5); // 休息页面底色（微绿）
  static const focusBg = Color(0xFFF6F8FA); // 专注页面底色

  static const amber = Color(0xFFF59E0B); // 连续天数/暂停按钮
  static const amberLight = Color(0xFFFEF3C7); // 暂停徽章底
  static const amberDark = Color(0xFFD97706); // 暂停徽章文字
  static const textDark = Color(0xFF2D3748); // 主文字 slate-800
  static const textMid = Color(0xFF64748B); // 次级文字 slate-500
  static const textGray = Color(0xFF94A3B8); // 弱化文字 slate-400
  static const slate50 = Color(0xFFF8FAFC); // 输入条底
  static const slate100 = Color(0xFFF1F5F9); // 分段控件底/空柱
  static const slate300 = Color(0xFFCBD5E1); // 勾选框描边
}

/// 韩系卡片：24px 圆角 + 描边 + 双层柔和阴影
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Gradient? gradient;
  final Color? borderColor;
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
    this.gradient,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor ?? AppColors.cardBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), offset: Offset(0, 10), blurRadius: 30),
          BoxShadow(color: Color(0x05000000), offset: Offset(0, 4), blurRadius: 12),
        ],
      ),
      child: child,
    );
  }
}
