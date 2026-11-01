import 'package:flutter/material.dart';

/// 全局配色（韩系简约风：珊瑚红 + 白卡片 + 浅灰底 + 休息绿）
/// 支持深色模式：AppColors.dark 为运行时开关，由 MaterialApp 每帧按主题模式写入。
/// 所有字段为 getter（非 const），引用处不可包在 const 表达式里。
class AppColors {
  /// 运行时深色标志（true = 深色主题生效）
  static bool dark = false;

  // ---------- 背景 / 卡片 ----------
  static Color get pageBg => dark ? const Color(0xFF0F172A) : const Color(0xFFF6F8FA); // 页面底
  static Color get card => dark ? const Color(0xFF1E293B) : Colors.white; // 卡片
  static Color get cardBorder => dark ? const Color(0x33334155) : const Color(0x80F0F2F5); // 卡片描边
  static Color get barBg => dark ? const Color(0xE61B2740) : const Color(0xE6FFFFFF); // 标题栏/导航半透明底
  static Color get dash => dark ? Colors.white24 : Colors.black26; // 虚线描边
  static Color get inputFill => dark ? const Color(0xFF223047) : const Color(0xFFF2F2F2); // 输入框底

  /// 弹窗卡片渐变（必须全实色，否则深色下会透出背景文字）
  static List<Color> get modalGradient =>
      dark ? const [Color(0xFF1E293B), Color(0xFF2B2026)] : const [Colors.white, Color(0xFFFFF8F8)];

  // ---------- 主色（珊瑚红，两套主题共用） ----------
  static const red = Color(0xFFFF5A5F);
  static const redDark = Color(0xFFE0484D);
  static Color get redLight => dark ? const Color(0x40FF5A5F) : const Color(0xFFFFE3E3); // 浅红底/徽章底
  static Color get redBg => dark ? const Color(0x26FF5A5F) : const Color(0xFFFFF5F5); // 红色浅背景
  static Color get headerBg => dark ? const Color(0xFF2A2226) : const Color(0xFFFFF7F7); // 头部卡片渐变起色

  // ---------- 休息绿 ----------
  static const green = Color(0xFF4EBA8E);
  static const greenDark = Color(0xFF3DA279);
  static Color get greenLight => dark ? const Color(0x404EBA8E) : const Color(0xFFD1F2E3); // 浅绿底/徽章底
  static Color get greenBg => dark ? const Color(0x264EBA8E) : const Color(0xFFEAF8F2); // 绿色浅背景
  static Color get breakBg => dark ? const Color(0xFF10201A) : const Color(0xFFF0FAF5); // 休息页面底色
  static Color get focusBg => pageBg; // 专注页面底色

  // ---------- 琥珀 ----------
  static const amber = Color(0xFFF59E0B);
  static Color get amberLight => dark ? const Color(0x33F59E0B) : const Color(0xFFFEF3C7); // 暂停徽章底
  static Color get amberDark => dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706); // 暂停徽章文字

  // ---------- 文字 ----------
  static Color get textDark => dark ? const Color(0xFFE2E8F0) : const Color(0xFF2D3748); // 主文字
  static Color get textMid => dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B); // 次级文字
  static Color get textGray => dark ? const Color(0xFF64748B) : const Color(0xFF94A3B8); // 弱化文字

  // ---------- 灰阶 ----------
  static Color get slate50 => dark ? const Color(0xFF223047) : const Color(0xFFF8FAFC); // 输入条底
  static Color get slate100 => dark ? const Color(0xFF253046) : const Color(0xFFF1F5F9); // 分段控件底/空柱
  static Color get slate300 => dark ? const Color(0xFF475569) : const Color(0xFFCBD5E1); // 勾选框描边
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
        boxShadow: [
          BoxShadow(
            color: AppColors.dark ? const Color(0x66000000) : const Color(0x08000000),
            offset: const Offset(0, 10),
            blurRadius: 30,
          ),
          BoxShadow(
            color: AppColors.dark ? const Color(0x44000000) : const Color(0x05000000),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: child,
    );
  }
}
