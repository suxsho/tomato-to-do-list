import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/tomato_view.dart';
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
    final raw = _nameCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先写下要做什么')));
      return;
    }
    // 快捷设置每个番茄时长：在文字里写 #数字（如「写代码 #15」表示该任务每个番茄 15 分钟）
    int pomoMin = 0;
    String name = raw;
    final m = RegExp(r'#\s*(\d{1,3})').firstMatch(raw);
    if (m != null) {
      pomoMin = (int.tryParse(m.group(1)!) ?? 0).clamp(0, 180);
      name = raw.replaceFirst(RegExp(r'#\s*\d{1,3}'), '').trim();
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先写下要做什么')));
      return;
    }
    context.read<AppState>().addTask(name, _estimated, pomoMin);
    _nameCtrl.clear();
    setState(() => _estimated = 1);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final todo = app.tasks.where((t) => !t.done).toList();
    final done = app.tasks.where((t) => t.done).toList();
    final estTotal = todo.fold<int>(0, (a, t) => a + t.estimated);

    // 左侧（竖屏时在上方）：今日概览 + 新建任务；右侧（竖屏时在下方）：待办与已完成
    final overview = <Widget>[
      _headerCard(app),
      _addCard(app),
      _ruleText(app),
      if (app.session != null) _sessionEntry(app),
    ];
    final tasks = <Widget>[
      _todoHeader(estTotal),
      ..._todoSection(app, todo),
      ..._doneSection(app, done),
    ];

    return LayoutBuilder(
      builder: (context, cons) {
        // PC 横屏：左右分栏，别把手机那套竖排一列拉满整个窗口
        if (cons.maxWidth >= 980) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1480),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 400,
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      children: overview,
                    ),
                  ),
                  Container(width: 1, color: AppColors.cardBorder),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 2, bottom: 24),
                      children: tasks,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [...overview, ...tasks],
        );
      },
    );
  }

  // ---------- 今日概览大卡片 ----------
  Widget _headerCard(AppState app) {
    return SoftCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.headerBg, AppColors.redBg]),
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
                    Text('${app.todayCount}', style: TextStyle(color: AppColors.textDark, fontSize: 40, fontWeight: FontWeight.w800, height: 1.1)),
                    const SizedBox(width: 4),
                    Text('个番茄', style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('专注 ${app.todayMinutes} 分钟 · 完成任务 ${app.doneTasksToday} 个 · 连续 ${app.streakDays} 天',
                    style: TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.w500)),
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
    );
  }

  // ---------- 添加新任务 ----------
  Widget _addCard(AppState app) {
    return SoftCard(
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textDark),
                    decoration: InputDecoration(
                      hintText: '要做什么？（默认 ${app.settings.focusMin} 分钟/个）',
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
              Padding(padding: EdgeInsets.only(left: 4), child: Text('预估要几个番茄', style: TextStyle(color: AppColors.textMid, fontSize: 12, fontWeight: FontWeight.w600))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    _miniBtn(icon: Icons.remove, onTap: () => setState(() => _estimated = (_estimated - 1).clamp(1, 24))),
                    SizedBox(
                      width: 30,
                      child: Text('$_estimated', textAlign: TextAlign.center, maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                    ),
                    _miniBtn(icon: Icons.add, onTap: () => setState(() => _estimated = (_estimated + 1).clamp(1, 24))),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text('提示：内容里加 #15 可把该任务设为每个番茄 15 分钟（不写则跟随默认）',
                style: TextStyle(color: AppColors.textGray, fontSize: 10, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ---------- 规则说明 ----------
  Widget _ruleText(AppState app) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
      child: Text(
        '番茄钟 ${app.settings.focusMin} / ${app.settings.shortBreakMin} / ${app.settings.longBreakMin} 分钟 · 每 ${app.settings.longBreakEvery} 个长休息（在设置中修改）',
        style: TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ---------- 进行中的番茄入口 ----------
  Widget _sessionEntry(AppState app) {
    return GestureDetector(
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
    );
  }

  // ---------- 待办标题 ----------
  Widget _todoHeader(int estTotal) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Text('待办 · 共预估 $estTotal 个番茄', style: TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  // ---------- 待办列表 ----------
  List<Widget> _todoSection(AppState app, List<Task> todo) {
    if (todo.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text('还没有待办，先添加一个吧', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGray, fontSize: 13)),
        ),
      ];
    }
    return [
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
    ];
  }

  // ---------- 已完成 ----------
  List<Widget> _doneSection(AppState app, List<Task> done) {
    if (done.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Row(
          children: [
            Expanded(child: Text('已完成', style: TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.bold))),
            GestureDetector(
              onTap: () => app.clearCompleted(),
              child: Text('清除已完成', style: TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
      ...done.map((t) => _TaskCard(task: t, dragIndex: null)),
    ];
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
                        color: isDone ? AppColors.textMid : AppColors.textDark,
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
                      Text('${task.completed}/${task.estimated} 个番茄 · 专注 ${task.focusSec ~/ 60} 分钟${task.pomoMin > 0 ? ' · 每番茄 ${task.pomoMin} 分' : ''}',
                          style: TextStyle(fontSize: 10, color: AppColors.textGray)),
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

    // 右键（桌面）/长按（移动端）弹出操作菜单：重新编辑 / 删除
    card = GestureDetector(
      onLongPress: () => _showTaskActions(context, task),
      onSecondaryTap: () => _showTaskActions(context, task),
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
            color: AppColors.card, // 实色打底，防止渐变透明导致透底
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppColors.modalGradient),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cardBorder),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark),
              ),
              const SizedBox(height: 8),
              Text(
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
                  child: Text('取消', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 长按 / 右键弹出的操作菜单：重新编辑 与 删除
  void _showTaskActions(BuildContext context, Task t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x660F172A),
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppColors.modalGradient),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.slate300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 6),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: AppColors.textMid),
                title: Text('重新编辑', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditTask(context, t);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.red),
                title: const Text('删除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, t);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 编辑任务弹窗：预填名称、预估番茄数与每个番茄时长；可修改后保存
  void _showEditTask(BuildContext context, Task t) {
    final nameCtrl = TextEditingController(text: t.name);
    int est = t.estimated;
    final minEst = t.completed == 0 ? 1 : t.completed;
    int pomo = t.pomoMin; // 0 = 跟随全局默认
    bool customPomo = t.pomoMin > 0;
    final globalFocus = context.read<AppState>().settings.focusMin;
    Widget miniBtn({required IconData icon, required VoidCallback onTap}) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4)]),
        child: Icon(icon, size: 14, color: AppColors.textMid),
      ),
    );
    showDialog(
      context: context,
      barrierColor: const Color(0x660F172A),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: (MediaQuery.of(ctx).size.width - 48).clamp(280.0, 360.0),
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppColors.modalGradient),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 16))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('编辑任务', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                          decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(16)),
                          child: TextField(
                            controller: nameCtrl,
                            autofocus: true,
                            onSubmitted: (_) => _commitEdit(ctx, t, nameCtrl.text, est, customPomo ? pomo : 0),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textDark),
                            decoration: InputDecoration(
                              hintText: '要做什么？',
                              hintStyle: TextStyle(color: AppColors.textGray, fontSize: 13, fontWeight: FontWeight.w500),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Padding(padding: EdgeInsets.only(left: 4), child: Text('预估要几个番茄', style: TextStyle(color: AppColors.textMid, fontSize: 12, fontWeight: FontWeight.w600))),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                children: [
                                  miniBtn(icon: Icons.remove, onTap: () => setSt(() => est = (est - 1).clamp(minEst, 24))),
                                  SizedBox(
                                    width: 30,
                                    child: Text('$est', textAlign: TextAlign.center, maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                                  ),
                                  miniBtn(icon: Icons.add, onTap: () => setSt(() => est = (est + 1).clamp(minEst, 24))),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text('自定义每个番茄时长', style: TextStyle(color: AppColors.textMid, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            Switch(
                              value: customPomo,
                              activeThumbColor: Colors.white,
                              activeTrackColor: AppColors.red,
                              onChanged: (v) => setSt(() {
                                customPomo = v;
                                if (v && pomo == 0) pomo = globalFocus;
                              }),
                            ),
                          ],
                        ),
                        if (customPomo) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Padding(padding: EdgeInsets.only(left: 4), child: Text('每个番茄', style: TextStyle(color: AppColors.textMid, fontSize: 12, fontWeight: FontWeight.w600))),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  children: [
                                    miniBtn(icon: Icons.remove, onTap: () => setSt(() => pomo = (pomo - 1).clamp(1, 180))),
                                    SizedBox(
                                      width: 34,
                                      child: Text('$pomo', textAlign: TextAlign.center, maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                                    ),
                                    miniBtn(icon: Icons.add, onTap: () => setSt(() => pomo = (pomo + 1).clamp(1, 180))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Text('跟随全局设置：$globalFocus 分钟 / 个', style: TextStyle(color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _commitEdit(ctx, t, nameCtrl.text, est, customPomo ? pomo : 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Color(0x29FF5A5F), blurRadius: 8, offset: Offset(0, 2))],
                    ),
                    child: const Text('保存', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                    child: Text('取消', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _commitEdit(BuildContext ctx, Task t, String name, int est, int pomoMin) {
    ctx.read<AppState>().updateTask(t.id, name, est, pomoMin);
    Navigator.pop(ctx);
  }
}
