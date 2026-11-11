import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 液态水波纹计时圆环（韩系风）：
/// 水位随已专注时间从底部上涨，波面平缓（小振幅正弦波），双层以不同速度流动
/// paused 时：波浪冻结 + 降饱和变浅（参考设计稿 is-paused 效果）
class WaveTimerView extends StatefulWidget {
  final double progress; // 已进行比例 0..1（0=空，1=满）
  final bool resting;
  final bool paused;
  /// 番茄已到点/结束：整圆切换成绿色（休息绿），让"完成了"一眼可见
  final bool finished;
  final double size;
  /// 强制浅色配色：透明桌面小窗口用它，避免深色主题下圆内透出桌面
  final bool forceLight;
  const WaveTimerView({
    super.key,
    required this.progress,
    this.resting = false,
    this.paused = false,
    this.finished = false,
    this.size = 220,
    this.forceLight = false,
  });

  @override
  State<WaveTimerView> createState() => _WaveTimerViewState();
}

class _WaveTimerViewState extends State<WaveTimerView> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    if (!widget.paused) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant WaveTimerView old) {
    super.didUpdateWidget(old);
    if (widget.paused && _ctrl.isAnimating) {
      _ctrl.stop();
    } else if (!widget.paused && !_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _WavePainter(
          progress: widget.progress.clamp(0.0, 1.0),
          resting: widget.resting,
          paused: widget.paused,
          finished: widget.finished,
          phase: _ctrl.value * 2 * math.pi,
          light: widget.forceLight,
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final bool resting;
  final bool paused;
  final bool finished;
  final double phase;
  final bool light;
  _WavePainter({
    required this.progress,
    required this.resting,
    required this.paused,
    required this.finished,
    required this.phase,
    required this.light,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    final circle = Rect.fromCircle(center: center, radius: r);

    // 到点（finished）与休息态共用绿色；绿色判断要排在 light 之前，
    // 否则 mini 小组件（forceLight=true）永远是粉色、看不出完成状态。
    final green = resting || finished;
    final bg = paused
        ? const Color(0xFFF8FAFC)
        : green
            ? (light ? const Color(0xFFEAF8F2) : AppColors.greenBg)
            : light
                ? const Color(0xFFFFF8F8)
                : AppColors.redBg;
    canvas.drawCircle(center, r, Paint()..color = bg);

    // 内部波浪（裁剪到圆内）
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    final levelY = center.dy + r - 2 * r * progress;
    final amp = r * 0.045;

    Color front, back;
    if (paused) {
      front = const Color(0x82D16E71); // 降饱和 40% + 透明度 0.6
      back = const Color(0x4DD16E71);
    } else if (green) {
      front = const Color(0xD94EBA8E);
      back = const Color(0x734EBA8E);
    } else {
      front = const Color(0xD9FF5A5F);
      back = const Color(0x73FF5A5F);
    }
    // light 模式下颜色固定，不读 AppColors（那套会随深色主题变半透明）

    void wave(Color c, double ph, double dy, double ampMul) {
      final path = Path();
      var first = true;
      // 空间频率取整数周期（x∈[-r,r] 恰好 2 个波），保证相位回绕时无缝循环
      for (var x = -r; x <= r; x += 4) {
        final y = levelY + dy + math.sin(x / r * math.pi * 2 + ph) * amp * ampMul;
        if (first) {
          path.moveTo(center.dx + x, y);
          first = false;
        } else {
          path.lineTo(center.dx + x, y);
        }
      }
      path.lineTo(center.dx + r, center.dy + r + 2);
      path.lineTo(center.dx - r, center.dy + r + 2);
      path.close();
      canvas.drawPath(path, Paint()..color = c);
    }

    // 背层波：位置明显更高、振幅更大、反向 2 倍速（整倍速保证循环无缝）→ 波峰露在前层水面上方
    wave(back, -phase * 2, -r * 0.10, 1.7);
    // 前层波
    wave(front, phase, 0, 1.0);
    canvas.restore();

    // 圆环描边（light 用固定浅粉，贴近设计稿的细粉圈）
    final strokeColor = paused
        ? const Color(0xFFF1F5F9)
        : green
            ? (light ? const Color(0xFFB6E8D3) : AppColors.greenLight)
            : light
                ? const Color(0xFFFFD3D7)
                : AppColors.redLight;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = strokeColor,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.progress != progress ||
      old.resting != resting ||
      old.paused != paused ||
      old.finished != finished ||
      old.phase != phase ||
      old.light != light;
}

/// 番茄视觉：
/// - level == null：虚线空圆（休息中）
/// - level 0..1：水位从满到空随剩余时间下降（专注中）
/// - full == true：完整番茄（开始前/头部图标）
/// - tint != null：单色剪影模式（用于导航小图标）
class TomatoView extends StatelessWidget {
  final double? level;
  final bool full;
  final double size;
  final Color? tint;
  const TomatoView({super.key, this.level, this.full = false, this.size = 240, this.tint});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * (full ? 1.05 : 1.0)),
      painter: _TomatoPainter(level: level, full: full, tint: tint),
    );
  }
}

class _TomatoPainter extends CustomPainter {
  final double? level;
  final bool full;
  final Color? tint;
  _TomatoPainter({required this.level, required this.full, this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2 + (full ? side * 0.03 : 0));
    final radius = side / 2 * (full ? 0.92 : 0.98);
    final circle = Rect.fromCircle(center: center, radius: radius);

    if (full) {
      _drawFullTomato(canvas, circle, center, radius);
      return;
    }

    // 虚线圆轮廓
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.dash;
    _drawDashedCircle(canvas, center, radius, dashPaint);

    final l = level ?? 0;
    if (l <= 0) return;

    // 水位（裁剪到圆内）
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    final surfaceY = center.dy + radius - 2 * radius * l;
    final fill = Paint()..color = AppColors.red;
    final path = Path()..moveTo(center.dx - radius, center.dy + radius + 2);
    path.lineTo(center.dx - radius, surfaceY);
    final waveAmp = math.min(6.0, radius * 0.05);
    for (var x = -radius; x <= radius; x += 4) {
      path.lineTo(center.dx + x, surfaceY + math.sin(x / radius * math.pi * 2) * waveAmp);
    }
    path.lineTo(center.dx + radius, center.dy + radius + 2);
    path.close();
    canvas.drawPath(path, fill);
    canvas.restore();
  }

  void _drawDashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const dash = 6.0;
    final circumference = 2 * math.pi * r;
    final steps = (circumference / (dash * 2)).ceil();
    for (var i = 0; i < steps; i++) {
      final a0 = i / steps * 2 * math.pi;
      final a1 = a0 + math.pi / steps;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, a1 - a0, false, paint);
    }
  }

  void _drawFullTomato(Canvas canvas, Rect circle, Offset center, double radius) {
    final bodyColor = tint ?? AppColors.red;
    final leafColor = tint ?? const Color(0xFF3BA55C);
    final shadeColor = tint == null ? const Color(0xFFE0484D) : tint!;

    // 主体圆
    canvas.drawCircle(center, radius, Paint()..color = bodyColor);

    // 底部柔和暗面（裁剪在主体内的月牙，不再是突兀的大圆块）
    if (tint == null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(circle));
      canvas.drawCircle(
        Offset(center.dx, center.dy + radius * 0.95),
        radius * 0.85,
        Paint()..color = shadeColor,
      );
      canvas.restore();
    }

    // 高光（剪影模式下不画）
    if (tint == null) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(center.dx - radius * 0.42, center.dy - radius * 0.28), width: radius * 0.5, height: radius * 0.34),
        Paint()..color = const Color(0x4DFFFFFF),
      );
    }

    if (tint != null) return; // 单色剪影到此为止

    // 萼叶：5 片尖叶从顶部中心呈星状散开，贴着番茄上沿
    final topY = center.dy - radius * 0.70;
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + (i - 2) * 0.62;
      final len = radius * (i == 2 ? 0.30 : 0.44);
      final dirX = math.cos(a), dirY = math.sin(a);
      final tip = Offset(center.dx + dirX * len, topY + dirY * len);
      // 每片叶：从中心出发、中间鼓、尖端收拢的柳叶形
      final leaf = Path()
        ..moveTo(center.dx, topY)
        ..quadraticBezierTo(
          center.dx + dirX * len * 0.45 - dirY * radius * 0.10,
          topY + dirY * len * 0.45 + dirX * radius * 0.10,
          tip.dx, tip.dy)
        ..quadraticBezierTo(
          center.dx + dirX * len * 0.45 + dirY * radius * 0.10,
          topY + dirY * len * 0.45 - dirX * radius * 0.10,
          center.dx, topY)
        ..close();
      canvas.drawPath(leaf, Paint()..color = leafColor);
    }
    // 短梗
    canvas.drawLine(
      Offset(center.dx, topY),
      Offset(center.dx + radius * 0.03, topY - radius * 0.22),
      Paint()
        ..color = leafColor
        ..strokeWidth = radius * 0.10
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TomatoPainter old) => old.level != level || old.full != full || old.tint != tint;
}
