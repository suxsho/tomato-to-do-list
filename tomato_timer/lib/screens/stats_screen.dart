import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/tomato_view.dart';

enum ChartMode { last7, last30, singleDay }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  ChartMode _mode = ChartMode.last7;
  int _taskMode = 0; // 0=近 7 天 1=全部 2=单日
  DateTime _taskDay = DateTime.now();
  DateTime _day = DateTime.now();

  String _dayLabel(int ts) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    return '${t.month}月${t.day}日 $hm';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final recent = app.records.reversed.take(30).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('专注统计', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 2),
              Text('完成的番茄才会计入，放弃的不算', style: TextStyle(fontSize: 11, color: AppColors.textGray, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        // 3 列指标卡
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Row(
            children: [
              _statCard('今日番茄', '${app.todayCount}', '个', AppColors.red),
              const SizedBox(width: 8),
              _statCard('今日专注', '${app.todayMinutes}', '分', AppColors.textDark),
              const SizedBox(width: 8),
              _statCard('连续天数', '${app.streakDays}', '天', AppColors.amber),
            ],
          ),
        ),
        // 图表卡片
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_mode == ChartMode.singleDay ? '单日番茄分布' : '近 ${_mode == ChartMode.last7 ? 7 : 30} 天番茄数',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  const Spacer(),
                  if (_mode == ChartMode.singleDay)
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.chevron_left, size: 18),
                          onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
                        ),
                        Text('${_day.month}/${_day.day}', style: TextStyle(fontSize: 12, color: AppColors.textGray, fontWeight: FontWeight.w600)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.chevron_right, size: 18),
                          onPressed: () {
                            final next = _day.add(const Duration(days: 1));
                            if (!next.isAfter(DateTime.now())) setState(() => _day = next);
                          },
                        ),
                      ],
                    )
                  else
                    Text('共 ${_mode == ChartMode.last7 ? app.dailyCounts(7).fold(0, (a, e) => a + e.$2) : app.dailyCounts(30).fold(0, (a, e) => a + e.$2)} 个',
                        style: TextStyle(fontSize: 11, color: AppColors.textGray, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              _segment(['近 7 天', '近 30 天', '单日'], _mode.index, (i) => setState(() => _mode = ChartMode.values[i])),
              const SizedBox(height: 12),
              SizedBox(height: 150, child: _buildChart(app)),
            ],
          ),
        ),
        // 按任务专注时长
        Builder(builder: (_) {
          final taskStats = app.taskFocusStats(last7: _taskMode == 0, day: _taskMode == 2 ? _taskDay : null);
          final maxMin = taskStats.fold<int>(1, (a, x) => x.$3 > a ? x.$3 : a);
          return SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('按任务的专注时长', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                    const Spacer(),
                    if (_taskMode == 2)
                      Row(
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chevron_left, size: 18),
                            onPressed: () => setState(() => _taskDay = _taskDay.subtract(const Duration(days: 1))),
                          ),
                          Text('${_taskDay.month}/${_taskDay.day}',
                              style: TextStyle(fontSize: 12, color: AppColors.textGray, fontWeight: FontWeight.w600)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chevron_right, size: 18),
                            onPressed: () {
                              final next = _taskDay.add(const Duration(days: 1));
                              if (!next.isAfter(DateTime.now())) setState(() => _taskDay = next);
                            },
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _segment(['近 7 天', '全部', '单日'], _taskMode, (i) => setState(() => _taskMode = i)),
                const SizedBox(height: 8),
                ...taskStats.asMap().entries.map((e) {
                  final (rank, name, minutes, count, otMin) = (e.key + 1, e.value.$2, e.value.$3, e.value.$4, e.value.$5);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('$rank', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, fontSize: 12)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark, fontSize: 12), overflow: TextOverflow.ellipsis)),
                            // 超过 1 分钟的到时超时（负计时）显示为 "25+1 分钟"
                            Text('$minutes${otMin > 0 ? '+$otMin' : ''} 分钟', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: minutes / maxMin,
                            minHeight: 6,
                            backgroundColor: AppColors.slate100,
                            color: AppColors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('$count 个番茄', style: TextStyle(fontSize: 10, color: AppColors.textGray)),
                      ],
                    ),
                  );
                }),
                if (taskStats.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('暂无数据', style: TextStyle(color: AppColors.textGray, fontSize: 12))),
              ],
            ),
          );
        }),
        // 最近的专注
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('最近专注记录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              const SizedBox(height: 4),
              ...recent.map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(r.taskName, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark, fontSize: 13)),
                    subtitle: Text(
                      '${_dayLabel(r.startTs)} · ${r.focusSec ~/ 60} 分钟${r.note.isNotEmpty ? ' · ${r.note}' : ''}',
                      style: TextStyle(fontSize: 10, color: AppColors.textGray),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('+1', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, fontSize: 12)),
                        const SizedBox(width: 3),
                        TomatoView(full: true, size: 13),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => app.deleteRecord(r.id),
                          child: Icon(Icons.close, size: 16, color: AppColors.textGray),
                        ),
                      ],
                    ),
                  )),
              if (recent.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('还没有完成的番茄', style: TextStyle(color: AppColors.textGray, fontSize: 12))),
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, String unit, Color valueColor) {
    return Expanded(
      child: SoftCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textGray)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor)),
                Text(unit, style: TextStyle(fontSize: 11, color: AppColors.textMid)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(List<String> labels, int selectedIndex, ValueChanged<int> onPick) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: List.generate(labels.length, (i) {
          final sel = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onPick(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? AppColors.red : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(labels[i], textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sel ? Colors.white : AppColors.textMid)),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildChart(AppState app) {
    if (_mode == ChartMode.singleDay) {
      final buckets = app.hourlyCounts(_day);
      final maxV = buckets.fold<int>(1, (a, b) => b > a ? b : a);
      return BarChart(BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxV + 1).toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              reservedSize: 20,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${v.toInt()}时', style: TextStyle(fontSize: 9, color: AppColors.textGray)),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var h = 0; h < 24; h++)
            BarChartGroupData(x: h, barRods: [
              BarChartRodData(
                toY: buckets[h].toDouble(),
                width: 7,
                color: buckets[h] > 0 ? AppColors.red : AppColors.slate100,
                borderRadius: BorderRadius.circular(3),
              ),
            ]),
        ],
      ));
    }
    final days = app.dailyCounts(_mode == ChartMode.last7 ? 7 : 30);
    final maxV = days.fold<int>(1, (a, e) => e.$2 > a ? e.$2 : a);
    final showEvery = _mode == ChartMode.last7 ? 1 : 5;
    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: (maxV + 1).toDouble(),
      borderData: FlBorderData(show: false),
      gridData: FlGridData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 20,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= days.length || i % showEvery != 0 && i != days.length - 1) return const SizedBox.shrink();
              final label = i == days.length - 1 ? '今天' : days[i].$1;
              final hot = i == days.length - 1 && days[i].$2 > 0;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(label, style: TextStyle(fontSize: 9, fontWeight: hot ? FontWeight.bold : FontWeight.normal, color: hot ? AppColors.red : AppColors.textGray)),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < days.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: days[i].$2.toDouble(),
              width: _mode == ChartMode.last7 ? 14 : 5,
              color: days[i].$2 > 0 ? AppColors.red : AppColors.slate100,
              borderRadius: BorderRadius.circular(3),
            ),
          ]),
      ],
    ));
  }
}
