import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'windows_flash.dart';

/// 全局应用状态：数据 + 计时核心逻辑
class AppState extends ChangeNotifier {
  static const _kTasks = 'tasks';
  static const _kRecords = 'records';
  static const _kSettings = 'settings';
  static const _kSession = 'session';

  late final SharedPreferences _prefs;
  final List<Task> tasks = [];
  final List<FocusRecord> records = [];
  Settings settings = Settings();
  Session? session;

  Timer? _ticker;
  final AudioPlayer _bellPlayer = AudioPlayer();
  final AudioPlayer _tickPlayer = AudioPlayer();
  String? _bellPath;
  String? _tickPath;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    tasks
      ..clear()
      ..addAll((_prefs.getString(_kTasks) ?? '').isEmpty
          ? []
          : (jsonDecode(_prefs.getString(_kTasks)!) as List).map((e) => Task.fromJson(e)));
    records
      ..clear()
      ..addAll((_prefs.getString(_kRecords) ?? '').isEmpty
          ? []
          : (jsonDecode(_prefs.getString(_kRecords)!) as List).map((e) => FocusRecord.fromJson(e)));
    if ((_prefs.getString(_kSettings) ?? '').isNotEmpty) {
      settings = Settings.fromJson(jsonDecode(_prefs.getString(_kSettings)!));
    }
    final s = _prefs.getString(_kSession);
    if (s != null && s.isNotEmpty) {
      session = Session.fromJson(jsonDecode(s));
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _onTick();
    notifyListeners();
  }

  // ---------- 持久化 ----------
  void _saveTasks() => _prefs.setString(_kTasks, jsonEncode(tasks.map((e) => e.toJson()).toList()));
  void _saveRecords() => _prefs.setString(_kRecords, jsonEncode(records.map((e) => e.toJson()).toList()));
  void _saveSettings() => _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
  void _saveSession() {
    if (session == null) {
      _prefs.remove(_kSession);
    } else {
      _prefs.setString(_kSession, jsonEncode(session!.toJson()));
    }
  }

  // ---------- 任务 ----------
  void addTask(String name, int estimated) {
    tasks.add(Task(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      estimated: estimated,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _saveTasks();
    notifyListeners();
  }

  void deleteTask(String id) {
    tasks.removeWhere((t) => t.id == id);
    _saveTasks();
    notifyListeners();
  }

  void toggleDone(Task t) {
    t.done = !t.done;
    _saveTasks();
    notifyListeners();
  }

  void reorderTasks(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final t = tasks.removeAt(oldIndex);
    tasks.insert(newIndex, t);
    _saveTasks();
    notifyListeners();
  }

  void clearCompleted() {
    tasks.removeWhere((t) => t.done);
    _saveTasks();
    notifyListeners();
  }

  Task? get currentTask => session == null ? null : tasks.where((t) => t.id == session!.taskId).firstOrNull;

  // ---------- 计时核心（按时间戳，关软件不中断） ----------
  /// 当前阶段已进行的秒数（扣除暂停）
  int get elapsedSec {
    final s = session!;
    var pausedMs = s.pausedAccumMs;
    if (s.pauseStartTs != null) {
      pausedMs += DateTime.now().millisecondsSinceEpoch - s.pauseStartTs!;
    }
    return ((DateTime.now().millisecondsSinceEpoch - s.startTs - pausedMs) / 1000).floor().clamp(0, 1 << 40);
  }

  /// 剩余秒数；为负表示到时后继续正计时的 overtime
  int get remainingSec => session!.durationSec - elapsedSec;

  /// 到时后已超出的秒数（用于负数正计时显示）
  int get overtimeSec => math.max(0, elapsedSec - session!.durationSec);

  void _onTick() {
    final s = session;
    if (s == null || s.isPaused) {
      notifyListeners();
      return;
    }
    if (!s.ended && elapsedSec >= s.durationSec) {
      if (s.phase == SessionPhase.focus) {
        // 自然到时：自动记录一个番茄，弹出结束提醒等待手动开始休息
        s.ended = true;
        _recordPomodoro(s.durationSec);
        _playBell();
        flashTaskbar(); // 最小化时任务栏图标闪红提醒
      } else if (s.phase == SessionPhase.shortBreak || s.phase == SessionPhase.longBreak) {
        // 休息结束：自动进入下一个番茄开始前界面
        s.phase = SessionPhase.preStart;
        s.startTs = DateTime.now().millisecondsSinceEpoch;
        s.pausedAccumMs = 0;
        s.pauseStartTs = null;
        s.durationSec = settings.focusMin * 60;
        s.ended = false;
        _playBell();
        flashTaskbar();
      }
      _saveSession();
    } else if (s.phase == SessionPhase.focus && !s.ended) {
      // 专注倒计时"咔咔"声（每秒一次，暂停时不响）
      _playTick();
    }
    notifyListeners();
  }

  void startTask(Task t) {
    if (session != null) return;
    session = Session(
      phase: SessionPhase.focus,
      taskId: t.id,
      taskName: t.name,
      startTs: DateTime.now().millisecondsSinceEpoch,
      durationSec: settings.focusMin * 60,
      pomodoroNo: 1,
    );
    _saveSession();
    notifyListeners();
  }

  void togglePause() {
    final s = session;
    if (s == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (s.pauseStartTs == null) {
      s.pauseStartTs = now;
    } else {
      s.pausedAccumMs += now - s.pauseStartTs!;
      s.pauseStartTs = null;
    }
    _saveSession();
    notifyListeners();
  }

  void updateNote(String note) {
    if (session == null) return;
    session!.note = note;
    _saveSession();
  }

  /// 提前点“结束”并选择记录：按实际已专注时长记录
  void finishEarly({required bool record}) {
    final s = session;
    if (s == null) return;
    if (record && s.phase == SessionPhase.focus) {
      final actual = math.min(elapsedSec, s.durationSec);
      _recordPomodoro(actual);
    }
    session = null;
    _saveSession();
    notifyListeners();
  }

  /// 到时提醒弹窗中点击“开始休息”
  void startBreak() {
    final s = session;
    if (s == null || s.phase != SessionPhase.focus) return;
    final isLong = s.cycleDone > 0 && s.cycleDone % settings.longBreakEvery == 0;
    s.phase = isLong ? SessionPhase.longBreak : SessionPhase.shortBreak;
    s.startTs = DateTime.now().millisecondsSinceEpoch;
    s.pausedAccumMs = 0;
    s.pauseStartTs = null;
    s.durationSec = (isLong ? settings.longBreakMin : settings.shortBreakMin) * 60;
    s.ended = false;
    _saveSession();
    notifyListeners();
  }

  void skipBreak() {
    final s = session;
    if (s == null || (s.phase != SessionPhase.shortBreak && s.phase != SessionPhase.longBreak)) return;
    s.phase = SessionPhase.preStart;
    s.startTs = DateTime.now().millisecondsSinceEpoch;
    s.pausedAccumMs = 0;
    s.pauseStartTs = null;
    s.durationSec = settings.focusMin * 60;
    s.ended = false;
    _saveSession();
    notifyListeners();
  }

  void startNextPomodoro() {
    final s = session;
    if (s == null || s.phase != SessionPhase.preStart) return;
    s.phase = SessionPhase.focus;
    s.startTs = DateTime.now().millisecondsSinceEpoch;
    s.pausedAccumMs = 0;
    s.pauseStartTs = null;
    s.durationSec = settings.focusMin * 60;
    s.ended = false;
    s.pomodoroNo += 1;
    s.note = '';
    _saveSession();
    notifyListeners();
  }

  /// “结束专注”：放弃后续流程，回到主界面
  void quitSession() {
    session = null;
    _saveSession();
    notifyListeners();
  }

  void _recordPomodoro(int focusSec) {
    final s = session!;
    final now = DateTime.now().millisecondsSinceEpoch;
    records.add(FocusRecord(
      id: now.toString(),
      taskId: s.taskId,
      taskName: s.taskName,
      note: s.note,
      startTs: s.startTs,
      endTs: now,
      focusSec: focusSec,
    ));
    if (s.taskId != null) {
      final t = tasks.where((e) => e.id == s.taskId).firstOrNull;
      if (t != null) {
        t.completed += 1;
        t.focusSec += focusSec;
        _saveTasks();
      }
    }
    s.cycleDone += 1;
    _saveRecords();
  }

  // ---------- 设置 ----------
  void updateSettings(Settings s) {
    settings = s;
    _saveSettings();
    notifyListeners();
  }

  void toggleSound() {
    settings.soundOn = !settings.soundOn;
    _saveSettings();
    notifyListeners();
  }

  // ---------- 统计 ----------
  DateTime _dayOf(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime(d.year, d.month, d.day);
  }

  List<FocusRecord> get todayRecords {
    final today = _dayOf(DateTime.now().millisecondsSinceEpoch);
    return records.where((r) => _dayOf(r.startTs) == today).toList();
  }

  int get todayCount => todayRecords.length;
  int get todayMinutes => todayRecords.fold<int>(0, (a, r) => a + r.focusSec) ~/ 60;

  int get doneTasksToday => tasks.where((t) => t.done).length;

  /// 连续天数（含今天；今天没有记录则从昨天往前数）
  int get streakDays {
    final days = records.map((r) => _dayOf(r.startTs)).toSet();
    var d = _dayOf(DateTime.now().millisecondsSinceEpoch);
    if (!days.contains(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// 近 N 天每日番茄数（最后一项为今天）
  List<(String, int)> dailyCounts(int days) {
    final result = <(String, int)>[];
    final today = _dayOf(DateTime.now().millisecondsSinceEpoch);
    for (var i = days - 1; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final count = records.where((r) => _dayOf(r.startTs) == d).length;
      result.add(('${d.month}/${d.day}', count));
    }
    return result;
  }

  /// 单日按小时分布
  List<int> hourlyCounts(DateTime day) {
    final buckets = List<int>.filled(24, 0);
    for (final r in records) {
      final t = DateTime.fromMillisecondsSinceEpoch(r.startTs);
      if (t.year == day.year && t.month == day.month && t.day == day.day) {
        buckets[t.hour]++;
      }
    }
    return buckets;
  }

  /// 按任务的专注时长（last7=true 时只统计近 7 天）
  List<(Task?, String, int, int)> taskFocusStats({required bool last7}) {
    final since = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final byName = <String, (int, int, String?)>{}; // name -> (sec, count, taskId)
    for (final r in records) {
      if (last7 && r.startTs < since) continue;
      final cur = byName[r.taskName] ?? (0, 0, r.taskId);
      byName[r.taskName] = (cur.$1 + r.focusSec, cur.$2 + 1, r.taskId);
    }
    final list = byName.entries
        .map((e) => (
              tasks.where((t) => t.id == e.value.$3).firstOrNull,
              e.key,
              e.value.$1 ~/ 60,
              e.value.$2,
            ))
        .toList()
      ..sort((a, b) => b.$3.compareTo(a.$3));
    return list;
  }

  // ---------- 备份 / 恢复 / 清除 ----------
  String exportJson() => jsonEncode({
        'app': 'tomato_timer',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': settings.toJson(),
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'records': records.map((e) => e.toJson()).toList(),
        'session': session?.toJson(),
      });

  bool importJson(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['app'] != 'tomato_timer') return false;
      settings = Settings.fromJson(j['settings'] as Map<String, dynamic>);
      tasks
        ..clear()
        ..addAll((j['tasks'] as List).map((e) => Task.fromJson(e)));
      records
        ..clear()
        ..addAll((j['records'] as List).map((e) => FocusRecord.fromJson(e)));
      session = j['session'] == null ? null : Session.fromJson(j['session'] as Map<String, dynamic>);
      _saveTasks();
      _saveRecords();
      _saveSettings();
      _saveSession();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void clearHistory() {
    records.clear();
    _saveRecords();
    notifyListeners();
  }

  void deleteRecord(String id) {
    records.removeWhere((r) => r.id == id);
    _saveRecords();
    notifyListeners();
  }

  // ---------- 提示音（运行时生成 WAV，无需外部资源） ----------
  /// 到时铃声（双音"叮—咚"）
  Future<void> _playBell() async {
    if (!settings.soundOn) return;
    try {
      await _ensureSounds();
      await _bellPlayer.stop();
      await _bellPlayer.play(DeviceFileSource(_bellPath!));
    } catch (_) {}
  }

  /// 专注倒计时"咔咔"声
  Future<void> _playTick() async {
    if (!settings.soundOn) return;
    try {
      await _ensureSounds();
      await _tickPlayer.stop();
      await _tickPlayer.play(DeviceFileSource(_tickPath!));
    } catch (_) {}
  }

  Future<void> _ensureSounds() async {
    if (_bellPath != null && _tickPath != null) return;
    final dir = await getTemporaryDirectory();
    final bell = File('${dir.path}${Platform.pathSeparator}tomato_bell.wav');
    if (!await bell.exists()) await bell.writeAsBytes(_buildWav(_bellSamples()));
    _bellPath = bell.path;
    final tick = File('${dir.path}${Platform.pathSeparator}tomato_tick.wav');
    if (!await tick.exists()) await tick.writeAsBytes(_buildWav(_tickSamples()));
    _tickPath = tick.path;
  }

  /// 把 -1..1 的采样列表打包成 16bit 单声道 WAV
  Uint8List _buildWav(List<double> samples) {
    const sampleRate = 44100;
    final n = samples.length;
    final data = Uint8List(44 + n * 2);
    final bd = ByteData.sublistView(data);
    void ascii(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        data[off + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    bd.setUint32(4, 36 + n * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bd.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      bd.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).toInt(), Endian.little);
    }
    return data;
  }

  /// 到时铃声：988Hz 短音 + 1319Hz 长音（叮—咚）
  List<double> _bellSamples() {
    const sr = 44100;
    const totalMs = 700;
    final out = List<double>.filled(sr * totalMs ~/ 1000, 0);
    void tone(double startMs, double durMs, double freq, double gain) {
      final start = startMs * sr ~/ 1000;
      final len = durMs * sr ~/ 1000;
      for (var i = 0; i < len && start + i < out.length; i++) {
        final t = i / sr;
        final env = math.exp(-t * 5.5) * math.min(1.0, t * 400);
        // 基音 + 一点泛音，更像铃
        final v = gain * env * (math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(2 * math.pi * freq * 2 * t));
        out[start + i] += v;
      }
    }

    tone(0, 250, 988, 0.35);
    tone(220, 480, 1319, 0.35);
    return out;
  }

  /// 倒计时"咔咔"声：两声短促咔哒（模拟机械滴答）
  List<double> _tickSamples() {
    const sr = 44100;
    const totalMs = 130;
    final out = List<double>.filled(sr * totalMs ~/ 1000, 0);
    void click(double startMs, double gain) {
      final start = startMs * sr ~/ 1000;
      final len = 28 * sr ~/ 1000;
      for (var i = 0; i < len && start + i < out.length; i++) {
        final t = i / sr;
        final env = math.exp(-t * 320);
        final v = gain * env * math.sin(2 * math.pi * 1900 * t);
        out[start + i] += v;
      }
    }

    click(0, 0.5);
    click(72, 0.35);
    return out;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _bellPlayer.dispose();
    _tickPlayer.dispose();
    super.dispose();
  }
}
