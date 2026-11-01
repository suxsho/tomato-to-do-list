import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

Future<void> showSettingsDialog(BuildContext context) {
  final app = context.read<AppState>();
  final s = app.settings;
  final focusCtrl = TextEditingController(text: '${s.focusMin}');
  final shortCtrl = TextEditingController(text: '${s.shortBreakMin}');
  final longCtrl = TextEditingController(text: '${s.longBreakMin}');
  final everyCtrl = TextEditingController(text: '${s.longBreakEvery}');

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('番茄钟设置'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _numField(ctx, focusCtrl, '专注时长（分钟）', 1, 120),
            _numField(ctx, shortCtrl, '短休息时长（分钟）', 1, 60),
            _numField(ctx, longCtrl, '长休息时长（分钟）', 1, 120),
            _numField(ctx, everyCtrl, '每几个番茄后长休息', 2, 12),
            Row(
              children: [
                const Expanded(child: Text('提示音', style: TextStyle(color: AppColors.textDark))),
                Switch(value: s.soundOn, activeTrackColor: AppColors.red, onChanged: (_) => app.toggleSound()),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () {
            int parse(TextEditingController c, int def, int min, int max) {
              final v = int.tryParse(c.text.trim());
              return v == null ? def : v.clamp(min, max);
            }

            app.updateSettings(Settings(
              focusMin: parse(focusCtrl, s.focusMin, 1, 120),
              shortBreakMin: parse(shortCtrl, s.shortBreakMin, 1, 60),
              longBreakMin: parse(longCtrl, s.longBreakMin, 1, 120),
              longBreakEvery: parse(everyCtrl, s.longBreakEvery, 2, 12),
              soundOn: app.settings.soundOn,
            ));
            Navigator.pop(ctx);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

Widget _numField(BuildContext ctx, TextEditingController ctrl, String label, int min, int max) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textDark))),
        SizedBox(
          width: 72,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF2F2F2),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
      ],
    ),
  );
}
