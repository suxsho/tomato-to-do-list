import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/tomato_view.dart';
import 'settings_dialog.dart';
import 'timer_flow_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameCtrl = TextEditingController();
  int _estimated = 1;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先写下要做什么')));
      return;
    }
    context.read<AppState>().addTask(name, _estimated);
    _nameCtrl.clear();
    setState(() => _estimated = 1);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final todo = app.tasks.where((t) => !t.done).toList();
    final done = app.tasks.where((t) => t.done).toList();
    final estTotal = todo.fold<int>(0, (a, t) => a + t.estimated);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        // 头部统计大卡片
        SoftCard(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          padding: const EdgeInsets.all(20),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.headerBg, AppColors.redBg]),
          borderColor: AppColors.redLight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TODAY'S FOCUS", style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${app.todayCount}', style: const TextStyle(color: AppColors.textDark, fontSize: 40, fontWeight: FontWeight.w800, height: 1.1)),
                        const SizedBox(width: 4),
                        const Text('个番茄', style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('专注 ${app.todayMinutes} 分钟 · 完成任务 ${app.doneTasksToday} 个 · 连续 ${app.streakDays} 天',
                        style: const TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.redLight)),
                child: Center(child: TomatoView(full: true, size: 40)),
              ),
            ],
          ),
        ),
        // 添加新任务卡片
        SoftCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        onSubmitted: (_) => _add(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textDark),
                        decoration: const InputDecoration(
                          hintText: '要做什么？',
                          hintStyle: TextStyle(color: AppColors.textGray, fontSize: 13, fontWeight: FontWeight.w500),
                          filled: false,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _add,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x29FF5A5F), blurRadius: 8, offset: Offset(0, 2))]),
                        child: const Text('添加', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Padding(padding: EdgeInsets.only(left: 4), child: Text('预估要几个番茄', style: TextStyle(color: AppColors.textMid, fontSize: 12, fontWeight: FontWeight.w600))),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        _miniBtn(icon: Icons.remove, onTap: () => setState(() => _estimated = (_estimated - 1).clamp(1, 24))),
                        SizedBox(
                          width: 30,
                          child: Text('$_estimated', textAlign: TextAlign.center, maxLines: 1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                        ),
                        _miniBtn(icon: Icons.add, onTap: () => setState(() => _estimated = (_estimated + 1).clamp(1, 24))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 规则说明 + 设置
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
          child: Row(
            children: [
              Expanded(
                child: Text('番茄钟 ${app.settings.focusMin} / ${app.settings.shortBreakMin} / ${app.settings.longBreakMin} 分钟 · 每 ${app.settings.longBreakEvery} 个长休息',
                    style: const TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              GestureDetector(
                onTap: () => showSettingsDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(12)),
                  child: const Text('设置', style: TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        // 进行中的番茄入口
        if (app.session != null)
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TimerFlowScreen())),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x29FF5A5F), blurRadius: 12, offset: Offset(0, 4))]),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('进行中的番茄：${app.session!.taskName}，点击继续',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        // 待办列表
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Text('待办 · 共预估 $estTotal 个番茄', style: const TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        if (todo.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('还没有待办，先添加一个吧', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGray, fontSize: 13)),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: todo.length,
            onReorder: (oldI, newI) => app.reorderTasks(oldI, newI),
            proxyDecorator: (child, index, anim) => ScaleTransition(scale: Tween<double>(begin: 1.0, end: 1.03).animate(anim), child: child),
            itemBuilder: (ctx, i) => _TaskCard(key: ValueKey(todo[i].id), task: todo[i], dragIndex: i),
          ),
        // 已完成
        if (done.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(
              children: [
                Expanded(child: Text('已完成', style: const TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.bold))),
                GestureDetector(
                  onTap: () => app.clearCompleted(),
                  child: const Text('清除已完成', style: TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          ...done.map((t) => _TaskCard(task: t, dragIndex: null)),
        ],
      ],
    );
  }

  Widget _miniBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4)]),
        child: Icon(icon, size: 14, color: AppColors.textMid),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final int? dragIndex; // null = 已完成，不参与拖拽
  const _TaskCard({super.key, required this.task, required this.dragIndex});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final busy = app.session != null;
    final isDone = task.done;

    Widget card = SoftCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Opacity(
        opacity: isDone ? 0.75 : 1,
        child: Row(
          children: [
            // 勾选圆钮
            GestureDetector(
              onTap: () => app.toggleDone(task),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? AppColors.red : Colors.transparent,
                  border: isDone ? null : Border.all(color: AppColors.slate300, width: 2),
                ),
                child: isDone ? const Icon(Icons.check, color: Colors.white, size: 13) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDone ? AppColors.textMid : const Color(0xFF334155),
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      )),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 番茄进度小图标：完成的画小番茄，未完成的画灰圈
                      ...List.generate(
                        task.estimated > 8 ? 8 : task.estimated,
                        (i) => Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: i < task.completed
                              ? TomatoView(full: true, size: 12)
                              : Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(color: AppColors.slate100, shape: BoxShape.circle, border: Border.all(color: AppColors.slate300, width: 1)),
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${task.completed}/${task.estimated} 个番茄 · 专注 ${task.focusSec ~/ 60} 分钟',
                          style: const TextStyle(fontSize: 10, color: AppColors.textGray)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isDone)
              GestureDetector(
                onTap: busy
                    ? null
                    : () {
                        app.startTask(task);
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TimerFlowScreen()));
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: busy ? AppColors.slate100 : AppColors.red,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: busy ? null : const [BoxShadow(color: Color(0x29FF5A5F), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: Text('开始', style: TextStyle(color: busy ? AppColors.textGray : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );

    // 右键（桌面）/长按（移动端）弹出删除
    card = GestureDetector(
      onLongPress: () => _confirmDelete(context, task),
      onSecondaryTap: () => _confirmDelete(context, task),
      child: card,
    );

    if (dragIndex != null) {
      card = ReorderableDragStartListener(index: dragIndex!, child: card);
    }
    return card;
  }

  void _confirmDelete(BuildContext context, Task t) {
    showDialog(
      context: context,
      barrierColor: const Color(0x660F172A),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFFFF8F8)]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white70),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 16))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 删除图标块
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.delete_outline, color: AppColors.red, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                '删除「${t.name}」？',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark),
              ),
              const SizedBox(height: 8),
              const Text(
                '该任务的番茄计数会保留在历史记录中。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMid, height: 1.6),
              ),
              const SizedBox(height: 22),
              // 删除按钮
              GestureDetector(
                onTap: () {
                  ctx.read<AppState>().deleteTask(t.id);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x66FF5A5F), blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: const Text('删除', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              // 取消按钮
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                  child: const Text('取消', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
