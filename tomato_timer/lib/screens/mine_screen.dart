import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

class MineScreen extends StatelessWidget {
  const MineScreen({super.key});

  Future<void> _backup(BuildContext context) async {
    final app = context.read<AppState>();
    final now = DateTime.now();
    final name = 'tomato_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
    final path = await FilePicker.platform.saveFile(dialogTitle: '备份到文件', fileName: name, type: FileType.custom, allowedExtensions: ['json']);
    if (path == null) return;
    await File(path).writeAsString(app.exportJson());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已备份到 $path')));
    }
  }

  Future<void> _restore(BuildContext context) async {
    final app = context.read<AppState>();
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result == null) return;
    final raw = await File(result.files.single.path!).readAsString();
    final ok = app.importJson(raw);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '恢复成功' : '备份文件格式不正确，恢复失败')));
    }
  }

  Future<void> _clearHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清除历史记录？'),
        content: const Text('将删除所有番茄专注记录，任务列表不受影响。此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认清除', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AppState>().clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // 顶部渐变卡
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFF43F5E), AppColors.red]),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Color(0x29FF5A5F), offset: Offset(0, 8), blurRadius: 20)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('番茄任务清单', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('任务配番茄，专注一个接一个', style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                child: const Text('版本 0.1.0 · 纯离线 · 零权限', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        // 提示音
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.volume_up, color: AppColors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('提示音', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    Text('专注时滴答声 · 结束时响铃提醒', style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
                  ],
                ),
              ),
              Switch(
                value: app.settings.soundOn,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.red,
                onChanged: (_) => app.toggleSound(),
              ),
            ],
          ),
        ),
        // 数据
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              _row(context, Icons.ios_share, '备份到文件', '导出一个 .json 备份文件', () => _backup(context)),
              const Divider(height: 1, indent: 60),
              _row(context, Icons.file_download_outlined, '从备份恢复', '选择之前保存的备份文件', () => _restore(context)),
              const Divider(height: 1, indent: 60),
              _row(context, Icons.delete_outline, '清除历史记录', '删除全部番茄专注记录', () => _clearHistory(context), showArrow: false, iconColor: const Color(0xFFF87171)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap, {bool showArrow = true, Color? iconColor}) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.textGray),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
      trailing: showArrow ? const Icon(Icons.chevron_right, color: AppColors.slate300, size: 18) : null,
      onTap: onTap,
    );
  }
}
