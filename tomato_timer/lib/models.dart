/// 数据模型：任务 / 专注记录 / 设置 / 进行中的计时会话
class Task {
  String id;
  String name;
  int estimated; // 预估番茄数
  int completed; // 已完成番茄数
  int focusSec; // 该任务累计专注秒数
  bool done;
  int createdAt;

  Task({
    required this.id,
    required this.name,
    required this.estimated,
    this.completed = 0,
    this.focusSec = 0,
    this.done = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'estimated': estimated,
        'completed': completed,
        'focusSec': focusSec,
        'done': done,
        'createdAt': createdAt,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        name: j['name'] as String,
        estimated: (j['estimated'] as num).toInt(),
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        focusSec: (j['focusSec'] as num?)?.toInt() ?? 0,
        done: j['done'] == true,
        createdAt: (j['createdAt'] as num).toInt(),
      );
}

/// 一条完成的番茄记录（放弃的不记录）
class FocusRecord {
  String id;
  String? taskId;
  String taskName;
  String note;
  int startTs; // 点击开始的时间戳（毫秒）
  int endTs; // 记录完成的时间戳
  int focusSec; // 实际专注秒数

  FocusRecord({
    required this.id,
    this.taskId,
    required this.taskName,
    this.note = '',
    required this.startTs,
    required this.endTs,
    required this.focusSec,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'taskName': taskName,
        'note': note,
        'startTs': startTs,
        'endTs': endTs,
        'focusSec': focusSec,
      };

  factory FocusRecord.fromJson(Map<String, dynamic> j) => FocusRecord(
        id: j['id'] as String,
        taskId: j['taskId'] as String?,
        taskName: j['taskName'] as String? ?? '',
        note: j['note'] as String? ?? '',
        startTs: (j['startTs'] as num).toInt(),
        endTs: (j['endTs'] as num).toInt(),
        focusSec: (j['focusSec'] as num).toInt(),
      );
}

class Settings {
  int focusMin;
  int shortBreakMin;
  int longBreakMin;
  int longBreakEvery; // 每几个番茄长休息
  bool soundOn;

  Settings({
    this.focusMin = 25,
    this.shortBreakMin = 5,
    this.longBreakMin = 30,
    this.longBreakEvery = 4,
    this.soundOn = true,
  });

  Map<String, dynamic> toJson() => {
        'focusMin': focusMin,
        'shortBreakMin': shortBreakMin,
        'longBreakMin': longBreakMin,
        'longBreakEvery': longBreakEvery,
        'soundOn': soundOn,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        focusMin: (j['focusMin'] as num?)?.toInt() ?? 25,
        shortBreakMin: (j['shortBreakMin'] as num?)?.toInt() ?? 5,
        longBreakMin: (j['longBreakMin'] as num?)?.toInt() ?? 30,
        longBreakEvery: (j['longBreakEvery'] as num?)?.toInt() ?? 4,
        soundOn: j['soundOn'] != false,
      );
}

enum SessionPhase { focus, shortBreak, longBreak, preStart }

/// 进行中的计时会话（持久化：按开始时间戳计时，关闭软件不中断）
class Session {
  SessionPhase phase;
  String? taskId;
  String taskName;
  int startTs; // 当前阶段开始时间戳
  int pausedAccumMs; // 暂停累计毫秒
  int? pauseStartTs; // 非空表示处于暂停中
  int durationSec; // 当前阶段计划时长
  bool ended; // 本阶段是否已到时（避免重复触发）
  int cycleDone; // 当前长休息周期内已完成番茄数
  int pomodoroNo; // 本次专注会话中是第几个番茄（从 1 开始）
  String note;

  Session({
    required this.phase,
    this.taskId,
    required this.taskName,
    required this.startTs,
    this.pausedAccumMs = 0,
    this.pauseStartTs,
    required this.durationSec,
    this.ended = false,
    this.cycleDone = 0,
    this.pomodoroNo = 1,
    this.note = '',
  });

  bool get isPaused => pauseStartTs != null;

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'taskId': taskId,
        'taskName': taskName,
        'startTs': startTs,
        'pausedAccumMs': pausedAccumMs,
        'pauseStartTs': pauseStartTs,
        'durationSec': durationSec,
        'ended': ended,
        'cycleDone': cycleDone,
        'pomodoroNo': pomodoroNo,
        'note': note,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        phase: SessionPhase.values.firstWhere((e) => e.name == j['phase'], orElse: () => SessionPhase.focus),
        taskId: j['taskId'] as String?,
        taskName: j['taskName'] as String? ?? '',
        startTs: (j['startTs'] as num).toInt(),
        pausedAccumMs: (j['pausedAccumMs'] as num?)?.toInt() ?? 0,
        pauseStartTs: (j['pauseStartTs'] as num?)?.toInt(),
        durationSec: (j['durationSec'] as num).toInt(),
        ended: j['ended'] == true,
        cycleDone: (j['cycleDone'] as num?)?.toInt() ?? 0,
        pomodoroNo: (j['pomodoroNo'] as num?)?.toInt() ?? 1,
        note: j['note'] as String? ?? '',
      );
}
