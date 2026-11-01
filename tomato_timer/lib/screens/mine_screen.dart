import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../webdav.dart';
import '../widgets/tomato_view.dart';

const _sky = Color(0xFF0EA5E9); // WebDAV 云同步主题色（对应原型 sky-500）

class MineScreen extends StatelessWidget {
  const MineScreen({super.key});

  // ---------- 文件备份 / 恢复 ----------

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
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('确认清除', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AppState>().clearHistory();
    }
  }

  // ---------- WebDAV ----------

  Future<void> _uploadCloud(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await app.uploadToCloud();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '已上传备份到云端' : (app.webdavStatus ?? '上传失败'))));
    }
  }

  Future<void> _restoreCloud(BuildContext context) async {
    final app = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('从云端恢复？'),
        content: const Text('将用云端最新一份备份覆盖当前的任务、记录与设置，此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('确认恢复', style: TextStyle(color: _sky))),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await app.restoreFromCloud();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '已从云端恢复最新备份' : (app.webdavStatus ?? '恢复失败'))));
    }
  }

  void _showWebdavConfig(BuildContext context) {
    final app = context.read<AppState>();
    final s = app.settings;
    final urlCtrl = TextEditingController(text: s.webdavUrl);
    final userCtrl = TextEditingController(text: s.webdavUser);
    final passCtrl = TextEditingController(text: s.webdavPass);
    final pathCtrl = TextEditingController(text: s.webdavPath);

    OutlineInputBorder border([BorderSide? side]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: side ?? BorderSide(color: AppColors.cardBorder),
        );

    String testing = ''; // '' = 空闲；'ing' = 测试中；其他 = 结果消息（注意：必须放在 builder 外，否则每次重建被重置）
    showDialog(
      context: context,
      barrierColor: const Color(0x660F172A),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: _sky.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.cloud_outlined, color: _sky, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WebDav 配置', style: TextStyle(fontSize: 16)),
                      Text('设置用于同步的服务器参数', style: TextStyle(fontSize: 11, color: AppColors.textGray, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field('服务器 URL', urlCtrl, 'https://dav.jianguoyun.com/dav/', border()),
                  _field('账号 / 用户名', userCtrl, '输入 WebDAV 账号', border(), false),
                  _field('密码 / 应用秘钥', passCtrl, '••••••••', border(), false, true),
                  _field('同步文件夹路径', pathCtrl, '/PomodoroData/', border()),
                ],
              ),
            ),
            actions: [
              if (testing == 'ing')
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _sky)),
                ),
              if (testing.isNotEmpty && testing != 'ing')
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(testing, style: TextStyle(fontSize: 11, color: testing.contains('成功') ? AppColors.green : AppColors.red)),
                ),
              TextButton(
                onPressed: testing == 'ing'
                    ? null
                    : () async {
                        setDialog(() => testing = 'ing');
                        final client = WebDavClient(
                          baseUrl: urlCtrl.text.trim(),
                          username: userCtrl.text.trim(),
                          password: passCtrl.text,
                          folder: pathCtrl.text.trim().isEmpty ? '/PomodoroData/' : pathCtrl.text.trim(),
                        );
                        try {
                          await client.testConnection();
                          setDialog(() => testing = '连接测试成功！');
                        } on WebDavException catch (e) {
                          setDialog(() => testing = e.message);
                        } catch (e) {
                          setDialog(() => testing = '连接失败：$e');
                        }
                      },
                child: Text(testing == 'ing' ? '测试中…' : '测试连接', style: TextStyle(color: AppColors.textMid)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _sky),
                onPressed: () {
                  app.saveWebdavConfig(
                    url: urlCtrl.text,
                    user: userCtrl.text,
                    pass: passCtrl.text,
                    path: pathCtrl.text,
                  );
                  Navigator.pop(ctx);
                },
                child: const Text('保存配置'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint, OutlineInputBorder border, [bool isUrl = true, bool obscure = false]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMid)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: isUrl ? TextInputType.url : TextInputType.text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textDark),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(fontSize: 12, color: AppColors.textGray),
              filled: true,
              fillColor: AppColors.slate50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              enabledBorder: border,
              focusedBorder: border,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 关于 ----------

  void _showAbout(BuildContext context) {
    showDialog(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(18)),
                child: Center(child: TomatoView(full: true, size: 38)),
              ),
              const SizedBox(height: 12),
              Text('番茄任务清单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 2),
              Text('Minimal Focus Timer v0.1.0', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textGray)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('软件作者', style: TextStyle(fontSize: 12, color: AppColors.textMid)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(6)),
                          child: Text('枫2', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.red)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: AppColors.cardBorder),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('任务配番茄，专注一个接一个。纯离线、零权限的极简效率工具。',
                          style: TextStyle(fontSize: 11, color: AppColors.textMid, height: 1.6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // B 站主页链接（可复制）
              GestureDetector(
                onLongPress: () {
                  Clipboard.setData(const ClipboardData(text: 'https://space.bilibili.com/10600'));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: const Color(0xFF00AEEC), borderRadius: BorderRadius.circular(12)),
                  child: const Text('B站主页：space.bilibili.com/10600（长按复制）',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                  child: Text('关闭', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 界面 ----------

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
              Icon(Icons.volume_up, color: AppColors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('提示音', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    Text('专注时滴答声 · 结束时响铃提醒', style: TextStyle(fontSize: 12, color: AppColors.textGray)),
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
        // 文件数据
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
        // WebDAV 云同步
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      leading: Icon(Icons.cloud_outlined, color: _sky),
                      title: Text('WebDav同步', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                      subtitle: Text(
                        app.settings.webdavConfigured ? '服务器已配置，可云备份 / 恢复' : '连接坚果云等 WebDAV 网盘',
                        style: TextStyle(fontSize: 11, color: AppColors.textGray),
                      ),
                    ),
                  ),
                  Switch(
                    value: app.settings.webdavOn,
                    activeThumbColor: Colors.white,
                    activeTrackColor: _sky,
                    onChanged: (_) => app.toggleWebdav(),
                  ),
                ],
              ),
              const Divider(height: 1, indent: 60),
              ListTile(
                enabled: app.settings.webdavOn,
                leading: Icon(Icons.sync, color: app.settings.webdavOn ? AppColors.textGray : AppColors.slate300),
                title: Text('自动同步记录', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: app.settings.webdavOn ? AppColors.textDark : AppColors.textGray)),
                subtitle: Text('完成一个番茄后自动上传备份', style: TextStyle(fontSize: 11, color: AppColors.textGray)),
                trailing: Switch(
                  value: app.settings.webdavOn && app.settings.webdavAutoSync,
                  activeThumbColor: Colors.white,
                  activeTrackColor: _sky,
                  onChanged: app.settings.webdavOn ? (_) => app.toggleWebdavAutoSync() : null,
                ),
              ),
              const Divider(height: 1, indent: 60),
              _row(context, Icons.tune, 'WebDav配置', '服务器 / 账号 / 密码 / 同步目录', () => _showWebdavConfig(context)),
              const Divider(height: 1, indent: 60),
              _row(context, Icons.cloud_upload_outlined, '上传备份到云端', '立即把当前数据备份到 WebDAV', () => _uploadCloud(context)),
              const Divider(height: 1, indent: 60),
              _row(context, Icons.cloud_download_outlined, '从云端恢复', '用云端最新备份覆盖本地数据', () => _restoreCloud(context)),
            ],
          ),
        ),
        // 同步状态
        if (app.webdavStatus != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 2),
            child: Text(app.webdavStatus!, style: TextStyle(fontSize: 11, color: AppColors.textGray)),
          ),
        // 关于
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _row(context, Icons.info_outline, '关于番茄任务清单与作者', '版本信息与联系方式', () => _showAbout(context)),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap, {bool showArrow = true, Color? iconColor}) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.textGray),
      title: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.textGray)),
      trailing: showArrow ? Icon(Icons.chevron_right, color: AppColors.slate300, size: 18) : null,
      onTap: onTap,
    );
  }
}
