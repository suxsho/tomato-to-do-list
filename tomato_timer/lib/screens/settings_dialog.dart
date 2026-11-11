import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

/// 番茄钟设置：专注 / 短休息 / 长休息 / 长休息周期
/// 深色模式在「我的」页外观卡片里，此处不再重复提供
/// 视觉与「结束本次番茄？」「专注设置」等弹窗保持一致
Future<void> showSettingsDialog(BuildContext context) {
  // 打开前先收键盘，避免弹窗关闭后输入框重新抢焦点
  FocusManager.instance.primaryFocus?.unfocus();
  return showDialog(
    context: context,
    barrierColor: const Color(0x660F172A),
    builder: (ctx) => const _SettingsPanel(),
  );
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel();

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late final TextEditingController _focusCtrl;
  late final TextEditingController _shortCtrl;
  late final TextEditingController _longCtrl;
  late final TextEditingController _everyCtrl;
  late bool _autoReset;
  late bool _dailyReset;
  late bool _noEstimate;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _focusCtrl = TextEditingController(text: '${s.focusMin}');
    _shortCtrl = TextEditingController(text: '${s.shortBreakMin}');
    _longCtrl = TextEditingController(text: '${s.longBreakMin}');
    _everyCtrl = TextEditingController(text: '${s.longBreakEvery}');
    _autoReset = s.autoResetAfterGap;
    _dailyReset = s.dailyResetOn;
    _noEstimate = s.noEstimate;
  }

  @override
  void dispose() {
    _focusCtrl.dispose();
    _shortCtrl.dispose();
    _longCtrl.dispose();
    _everyCtrl.dispose();
    super.dispose();
  }

  int _parse(TextEditingController c, int def, int min, int max) {
    final v = int.tryParse(c.text.trim());
    return v == null ? def : v.clamp(min, max);
  }

  void _save() {
    final app = context.read<AppState>();
    final cur = app.settings;
    final next = Settings.fromJson(cur.toJson());
    next.focusMin = _parse(_focusCtrl, cur.focusMin, 1, 120);
    next.shortBreakMin = _parse(_shortCtrl, cur.shortBreakMin, 1, 60);
    next.longBreakMin = _parse(_longCtrl, cur.longBreakMin, 1, 120);
    next.longBreakEvery = _parse(_everyCtrl, cur.longBreakEvery, 2, 12);
    next.themeMode = cur.themeMode; // 主题在「我的」外观里改，这里保持原值
    next.autoResetAfterGap = _autoReset;
    next.dailyResetOn = _dailyReset;
    next.noEstimate = _noEstimate;
    app.updateSettings(next);
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.82;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Container(
        width: 380,
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: AppColors.card, // 实色打底，防止渐变透底
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppColors.modalGradient),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题区
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(14)),
                    child: const Center(child: Icon(Icons.timer_outlined, size: 24, color: AppColors.red)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('番茄钟设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                        const SizedBox(height: 2),
                        Text('专注与休息的节奏', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textGray)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: AppColors.slate100, shape: BoxShape.circle),
                      child: Icon(Icons.close, size: 16, color: AppColors.textMid),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.cardBorder),
            // 表单
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Column(
                  children: [
                    _numRow(
                      icon: Icons.center_focus_strong,
                      label: '专注时长',
                      hint: '一个番茄的时间',
                      ctrl: _focusCtrl,
                      unit: '分钟',
                      onChanged: () => setState(() {}),
                    ),
                    _numRow(
                      icon: Icons.coffee_outlined,
                      label: '短休息',
                      hint: '每个番茄之后',
                      ctrl: _shortCtrl,
                      unit: '分钟',
                      onChanged: () => setState(() {}),
                    ),
                    _numRow(
                      icon: Icons.self_improvement,
                      label: '长休息',
                      hint: '走完一个周期后',
                      ctrl: _longCtrl,
                      unit: '分钟',
                      onChanged: () => setState(() {}),
                    ),
                    _numRow(
                      icon: Icons.repeat,
                      label: '长休息周期',
                      hint: '每几个番茄长休息一次',
                      ctrl: _everyCtrl,
                      unit: '个',
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    // 节奏预览
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(14)),
                      child: Text(
                        '专注 ${_parse(_focusCtrl, 25, 1, 120)} 分钟 · 短休息 ${_parse(_shortCtrl, 5, 1, 60)} 分钟\n每 ${_parse(_everyCtrl, 4, 2, 12)} 个番茄后，长休息 ${_parse(_longCtrl, 30, 1, 120)} 分钟',
                        style: TextStyle(fontSize: 11, height: 1.7, fontWeight: FontWeight.w600, color: AppColors.textMid),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 长期使用 / 免勾选完成 的三个开关
                    _switchRow(
                      icon: Icons.restart_alt,
                      label: '久置自动重置周期',
                      hint: '距上次休息超过其时长，下次开始归零番茄周期',
                      value: _autoReset,
                      onChanged: (v) => setState(() => _autoReset = v),
                    ),
                    const SizedBox(height: 8),
                    _switchRow(
                      icon: Icons.calendar_month_outlined,
                      label: '每天番茄清零',
                      hint: '以次日凌晨 5:00 为界，跨天把任务番茄进度重置为 0（历史统计保留）',
                      value: _dailyReset,
                      onChanged: (v) => setState(() => _dailyReset = v),
                    ),
                    const SizedBox(height: 8),
                    _switchRow(
                      icon: Icons.all_inclusive,
                      label: '无总番茄预估',
                      hint: '不用填预估番茄数，任务不会结束，可长期反复计时',
                      value: _noEstimate,
                      onChanged: (v) => setState(() => _noEstimate = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: AppColors.cardBorder),
            // 操作区
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(14)),
                        child: Text('取消',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _save,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [BoxShadow(color: Color(0x55FF5A5F), blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        child: const Text('保存',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: value ? AppColors.red : AppColors.textGray),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 2),
                Text(hint, style: TextStyle(fontSize: 10, height: 1.35, fontWeight: FontWeight.w500, color: AppColors.textGray)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.red,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _numRow({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController ctrl,
    required String unit,
    required VoidCallback onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textGray),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  Text(hint, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textGray)),
                ],
              ),
            ),
            Container(
              width: 52,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(9)),
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                onChanged: (_) => onChanged(),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textDark),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 26,
              child: Text(unit, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textGray)),
            ),
          ],
        ),
      ),
    );
  }
}
