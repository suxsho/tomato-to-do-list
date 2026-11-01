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
            // 深色模式（默认跟随系统），放在最上面
            _themeModeSelector(ctx, app, s),
            _numField(ctx, focusCtrl, '专注时长（分钟）', 1, 120),
            _numField(ctx, shortCtrl, '短休息时长（分钟）', 1, 60),
            _numField(ctx, longCtrl, '长休息时长（分钟）', 1, 120),
            _numField(ctx, everyCtrl, '每几个番茄后长休息', 2, 12),
            Row(
              children: [
                Expanded(child: Text('提示音', style: TextStyle(color: AppColors.textDark))),
                Switch(value: s.soundOn, activeTrackColor: AppColors.red, onChanged: (_) => app.toggleSound()),
              ],
            ),
            // 音量调节（提示音开启时可用）
            StatefulBuilder(
              builder: (ctx, setLocal) {
                return Row(
                  children: [
                    Icon(
                      s.volume <= 0.01 ? Icons.volume_off : s.volume < 0.5 ? Icons.volume_down : Icons.volume_up,
                      size: 18,
                      color: s.soundOn ? AppColors.red : AppColors.slate300,
                    ),
                    Expanded(
                      child: Slider(
                        value: s.volume,
                        min: 0.0,
                        max: 1.0,
                        activeColor: AppColors.red,
                        onChanged: s.soundOn ? (v) => setLocal(() => s.volume = v) : null,
                        onChangeEnd: (v) {
                          app.setVolume(v);
                          if (v > 0.01) app.previewTick(); // 松手试听一声
                        },
                      ),
                    ),
                    SizedBox(
                      width: 38,
                      child: Text('${(s.volume * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMid)),
                    ),
                  ],
                );
              },
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
              volume: app.settings.volume,
              themeMode: app.settings.themeMode,
              webdavOn: app.settings.webdavOn,
              webdavAutoSync: app.settings.webdavAutoSync,
              webdavUrl: app.settings.webdavUrl,
              webdavUser: app.settings.webdavUser,
              webdavPass: app.settings.webdavPass,
              webdavPath: app.settings.webdavPath,
            ));
            Navigator.pop(ctx);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

/// 深色模式三段选择：跟随系统 / 浅色 / 深色（即时生效）
Widget _themeModeSelector(BuildContext ctx, AppState app, Settings s) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text('深色模式', style: TextStyle(fontSize: 14, color: AppColors.textDark))),
            ],
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'system', label: Text('跟随系统')),
            ButtonSegment(value: 'light', label: Text('浅色')),
            ButtonSegment(value: 'dark', label: Text('深色')),
          ],
          selected: {s.themeMode},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.redLight,
            selectedForegroundColor: AppColors.red,
            backgroundColor: AppColors.slate100,
            foregroundColor: AppColors.textMid,
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            visualDensity: VisualDensity.compact,
          ),
          onSelectionChanged: (sel) => app.setThemeMode(sel.first),
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
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: AppColors.textDark))),
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
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
      ],
    ),
  );
}
