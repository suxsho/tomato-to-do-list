import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'screen_keep_on.dart';
import 'system_notify.dart';
import 'webdav.dart';
import 'windows_flash.dart';

/// 全局应用状态：数据 + 计时核心逻辑
class AppState extends ChangeNotifier {
  static const _kTasks = 'tasks';
  static const _kRecords = 'records';
  static const _kSettings = 'settings';
  static const _kSession = 'session';
  static const _kCycleDone = 'cycleDone';
  static const _kLastChange = 'lastChangeTs';

  late final SharedPreferences _prefs;
  final List<Task> tasks = [];
  final List<FocusRecord> records = [];
  Settings settings = Settings();
  Session? session;

  /// 自上次长休息以来已完成的番茄数（全局累计，跨任务/跨会话，重启不丢）
  int cycleDone = 0;

  /// 本地数据最后一次变更时间（用于启动自动同步判断谁更新）
  int _lastChangeTs = 0;

  /// 最近一次 WebDAV 同步状态提示（null = 无）
  String? webdavStatus;

  Timer? _ticker;
  bool _syncing = false;
  bool? _keepOnApplied; // 上次应用的屏幕常亮状态（避免重复调用通道）
  final AudioPlayer _bellPlayer = AudioPlayer();
  final AudioPlayer _tickPlayer = AudioPlayer();
  String? _bellPath;
  static const _tickAsset = 'sounds/tick.wav'; // 打包的"咔咔"声音效

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
    cycleDone = _prefs.getInt(_kCycleDone) ?? 0;
    _lastChangeTs = _prefs.getInt(_kLastChange) ?? 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _onTick();
    // 恢复未结束会话后应用屏幕常亮状态
    _applyKeepScreenOn();
    // 系统深浅色切换时，若主题为"跟随系统"则刷新界面
    PlatformDispatcher.instance.onPlatformBrightnessChanged = () {
      if (settings.themeMode == 'system') notifyListeners();
    };
    notifyListeners();
    // 安卓 13+ 通知权限（开关打开时才申请）
    if (settings.notifyOn) {
      unawaited(SystemNotify.requestPermission());
    }
    // 开了自动同步：启动第一时间与云端比对，避免多设备切换后数据滞后
    if (settings.webdavOn && settings.webdavAutoSync && settings.webdavConfigured) {
      unawaited(syncOnLaunch());
    }
  }

  // ---------- 持久化 ----------
  /// 记录本地变更时间（启动自动同步时与云端 exportedAt 比较）
  void _markChanged() {
    _lastChangeTs = DateTime.now().millisecondsSinceEpoch;
    _prefs.setInt(_kLastChange, _lastChangeTs);
  }

  void _saveTasks() {
    _prefs.setString(_kTasks, jsonEncode(tasks.map((e) => e.toJson()).toList()));
    _markChanged();
  }

  void _saveRecords() {
    _prefs.setString(_kRecords, jsonEncode(records.map((e) => e.toJson()).toList()));
    _markChanged();
  }

  void _saveSettings() {
    _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
    _markChanged();
  }

  void _saveCycle() {
    _prefs.setInt(_kCycleDone, cycleDone);
    _markChanged();
  }

  /// 会话持久化：所有会话状态变化都会经过这里，顺带应用屏幕常亮
  void _saveSession() {
    if (session == null) {
      _prefs.remove(_kSession);
    } else {
      _prefs.setString(_kSession, jsonEncode(session!.toJson()));
    }
    _markChanged();
    _applyKeepScreenOn();
  }

  /// 屏幕常亮：仅安卓生效；会话进行中且开关打开时保持常亮
  void _applyKeepScreenOn() {
    if (!ScreenKeepOn.supported) return;
    final should = settings.keepScreenOn && session != null;
    if (_keepOnApplied == should) return;
    _keepOnApplied = should;
    ScreenKeepOn.set(should);
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

  /// 下一次休息是否应该是长休息：已完成番茄数达到设定周期
  bool get nextBreakIsLong =>
      cycleDone > 0 && settings.longBreakEvery > 0 && cycleDone % settings.longBreakEvery == 0;

  /// 当前周期内已完成的番茄数（用于界面圆点），刚凑满或长休息中显示为满格
  int get cycleProgress {
    final every = settings.longBreakEvery <= 0 ? 4 : settings.longBreakEvery;
    final s = session;
    if (s != null && s.phase == SessionPhase.longBreak) return every;
    if (cycleDone > 0 && cycleDone % every == 0) return every;
    return cycleDone % every;
  }

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
        _vibrate();
        flashTaskbar(); // 最小化时任务栏图标闪红提醒
        final breakMin = nextBreakIsLong ? settings.longBreakMin : settings.shortBreakMin;
        _notifyDone(
          title: '番茄时间到 · 该休息了',
          body: s.taskName.isNotEmpty
              ? '「${s.taskName}」完成第 ${s.pomodoroNo} 个番茄，休息 $breakMin 分钟吧'
              : '本次专注完成，休息 $breakMin 分钟吧',
        );
      } else if (s.phase == SessionPhase.shortBreak || s.phase == SessionPhase.longBreak) {
        // 休息结束：自动进入下一个番茄开始前界面
        s.phase = SessionPhase.preStart;
        s.startTs = DateTime.now().millisecondsSinceEpoch;
        s.pausedAccumMs = 0;
        s.pauseStartTs = null;
        s.durationSec = settings.focusMin * 60;
        s.ended = false;
        _playBell();
        _vibrate();
        flashTaskbar();
        _notifyDone(
          title: '休息结束 · 开始下一个番茄',
          body: '专注 ${settings.focusMin} 分钟，继续保持节奏',
        );
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

  /// 提前点“结束”：
  /// - 未到时 + 选择记录：记录一个番茄后按周期进入短/长休息，会话不中断
  /// - 未到时 + 放弃：直接结束会话回主界面
  /// - 已自然到时：补记超时后结束会话（到时提醒浮层里另有“开始休息”入口）
  void finishEarly({required bool record}) {
    final s = session;
    if (s == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (s.phase == SessionPhase.focus) {
      if (s.ended) {
        // 已自然到时并记录过番茄：只补记超时（负计时），不重复记录
        _applyOvertime();
        session = null;
        _saveSession();
        notifyListeners();
        return;
      }
      if (record) {
        // 未到时提前结束但记录：按实际已专注时长记录，然后按周期进入短/长休息
        final actual = math.min(elapsedSec, s.durationSec);
        _recordPomodoro(actual);
        _enterBreak(s, now);
        return;
      }
    }
    session = null;
    _saveSession();
    notifyListeners();
  }

  /// 进入休息阶段（按全局番茄周期判断短/长休息），长休息开始后周期归零
  void _enterBreak(Session s, int now) {
    final isLong = nextBreakIsLong;
    s.phase = isLong ? SessionPhase.longBreak : SessionPhase.shortBreak;
    s.startTs = now;
    s.pausedAccumMs = 0;
    s.pauseStartTs = null;
    s.durationSec = (isLong ? settings.longBreakMin : settings.shortBreakMin) * 60;
    s.ended = false;
    if (isLong) {
      // 一个完整周期结束：计数归零，开启下一个周期
      cycleDone = 0;
      _saveCycle();
    }
    _saveSession();
    notifyListeners();
  }

  /// 到时提醒浮层里的“丢弃该番茄”：用于计时一直开着、人其实早就离开（忘记关闭）的情况。
  /// 本次番茄不计入统计：回滚自动写入的记录、任务累计与周期计数，然后结束会话回主界面。
  void discardPomodoro() {
    final s = session;
    if (s == null) return;
    if (s.phase == SessionPhase.focus && s.ended) {
      _discardLastRecord(s);
    }
    session = null;
    _saveSession();
    notifyListeners();
  }

  /// 找到本次会话刚记录的那条番茄并整体回滚
  void _discardLastRecord(Session s) {
    final idx = records.lastIndexWhere((r) => r.startTs == s.startTs && r.taskId == s.taskId);
    if (idx < 0) return;
    final r = records.removeAt(idx);
    if (s.taskId != null) {
      final t = tasks.where((e) => e.id == s.taskId).firstOrNull;
      if (t != null) {
        t.completed = math.max(0, t.completed - 1);
        t.focusSec = math.max(0, t.focusSec - r.focusSec);
        _saveTasks();
      }
    }
    cycleDone = math.max(0, cycleDone - 1);
    s.cycleDone = cycleDone;
    _saveCycle();
    _saveRecords();
    // 丢弃后立刻同步一次，避免云端还留着这条已作废的记录
    if (settings.webdavOn && settings.webdavAutoSync && settings.webdavConfigured) {
      uploadToCloud(auto: true);
    }
  }

  /// 到时提醒弹窗中点击“开始休息”
  void startBreak() {
    final s = session;
    if (s == null || s.phase != SessionPhase.focus) return;
    _applyOvertime(); // 补记等待期间的超时分钟
    _enterBreak(s, DateTime.now().millisecondsSinceEpoch);
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
    // 跳过休息直接开下一轮时，超时已在 startBreak/skipBreak 前补记
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
    cycleDone += 1;
    s.cycleDone = cycleDone; // 兼容旧会话字段（仅用于展示/导出）
    _saveCycle();
    _saveRecords();
    // 自动同步：完成一个番茄后把备份上传到 WebDAV
    if (settings.webdavOn && settings.webdavAutoSync && settings.webdavConfigured) {
      uploadToCloud(auto: true);
    }
  }

  /// 自然到时后用户停留期间产生的超时秒数（负计时），补记到刚才那条记录上。
  /// 只在“到时已记录、尚未进入下一阶段”的窗口内生效一次。
  void _applyOvertime() {
    final s = session;
    if (s == null || s.phase != SessionPhase.focus || !s.ended) return;
    final ot = math.max(0, elapsedSec - s.durationSec);
    if (ot <= 0 || records.isEmpty) return;
    final r = records.last;
    if (r.overtimeSec == 0 && r.focusSec == s.durationSec && r.taskId == s.taskId) {
      r.overtimeSec = ot;
      _saveRecords();
    }
  }

  // ---------- 设置 ----------
  void updateSettings(Settings s) {
    settings = s;
    _saveSettings();
    _applyKeepScreenOn();
    notifyListeners();
  }

  /// 深色模式：'system'（跟随系统，默认）/ 'light' / 'dark'
  void setThemeMode(String mode) {
    settings.themeMode = mode;
    _saveSettings();
    notifyListeners();
  }

  void toggleSound() {
    settings.soundOn = !settings.soundOn;
    _saveSettings();
    notifyListeners();
  }

  /// 防烧屏模式开关（专注设置弹窗）
  void toggleBurnInProtect() {
    settings.burnInProtectOn = !settings.burnInProtectOn;
    _saveSettings();
    notifyListeners();
  }

  /// 屏幕常亮开关（仅安卓设置页可见）
  void toggleKeepScreenOn() {
    settings.keepScreenOn = !settings.keepScreenOn;
    _saveSettings();
    _applyKeepScreenOn();
    notifyListeners();
  }

  /// 到时震动提醒开关（仅安卓生效/可见）
  void toggleVibrate() {
    settings.vibrateOn = !settings.vibrateOn;
    _saveSettings();
    notifyListeners();
  }

  /// 到时系统通知开关（安卓通知栏 / Windows 托盘气泡）
  void toggleNotify() {
    settings.notifyOn = !settings.notifyOn;
    _saveSettings();
    if (settings.notifyOn) {
      unawaited(SystemNotify.requestPermission());
      // 打开时发一条示例，顺便确认通知权限是否已授予
      _notifyDone(title: '通知已开启', body: '番茄到时会在通知栏提醒你');
    }
    notifyListeners();
  }

  /// 调节提示音音量（0.0 ~ 1.0），立即生效
  void setVolume(double v) {
    settings.volume = v.clamp(0.0, 1.0);
    _saveSettings();
    _bellPlayer.setVolume(settings.volume);
    _tickPlayer.setVolume(settings.volume);
    notifyListeners();
  }

  // ---------- WebDAV ----------
  WebDavClient? _webdavClient() {
    if (!settings.webdavConfigured) return null;
    return WebDavClient(
      baseUrl: settings.webdavUrl,
      username: settings.webdavUser,
      password: settings.webdavPass,
      folder: settings.webdavPath,
    );
  }

  void toggleWebdav() {
    settings.webdavOn = !settings.webdavOn;
    _saveSettings();
    notifyListeners();
    if (settings.webdavOn && settings.webdavAutoSync) unawaited(syncOnLaunch());
  }

  void toggleWebdavAutoSync() {
    settings.webdavAutoSync = !settings.webdavAutoSync;
    _saveSettings();
    notifyListeners();
    // 刚打开自动同步就先对齐一次，不用等下一个番茄
    if (settings.webdavOn && settings.webdavAutoSync) unawaited(syncOnLaunch());
  }

  void saveWebdavConfig({required String url, required String user, required String pass, required String path}) {
    settings.webdavUrl = url.trim();
    settings.webdavUser = user.trim();
    settings.webdavPass = pass;
    settings.webdavPath = path.trim().isEmpty ? '/PomodoroData/' : path.trim();
    _saveSettings();
    notifyListeners();
  }

  void _setWebdavStatus(String? msg) {
    webdavStatus = msg;
    notifyListeners();
  }

  /// 固定的云端备份文件名（每次覆盖，避免云端堆积大量带时间戳的文件）
  static const String cloudBackupName = 'tomato_backup.json';
  /// 旧版本遗留的带时间戳备份文件（tomato_backup_20261101_232002.json）保留最近几份作历史
  static const int _keepOldBackups = 3;

  /// 上传备份到云端（auto=true 表示自动同步触发，静默失败仅记状态）
  Future<bool> uploadToCloud({bool auto = false}) async {
    if (_syncing) return false;
    final client = _webdavClient();
    if (client == null) {
      if (!auto) _setWebdavStatus('请先在 WebDav 配置中填写服务器信息');
      return false;
    }
    _syncing = true;
    if (!auto) _setWebdavStatus('正在上传备份…');
    try {
      await client.upload(cloudBackupName, exportJson());
      _setWebdavStatus('已同步到云端 $cloudBackupName');
      // 顺手清理旧版带时间戳的备份文件，只保留最近几份作历史（失败不影响本次同步）
      try {
        final old = (await client.listBackups())
            .where((n) => n.startsWith('tomato_backup_') && n.endsWith('.json'))
            .toList();
        for (final n in old.skip(_keepOldBackups)) {
          await client.delete(n);
        }
      } catch (_) {}
      return true;
    } on WebDavException catch (e) {
      _setWebdavStatus(auto ? '自动同步失败：${e.message}' : e.message);
    } catch (e) {
      _setWebdavStatus('上传失败：$e');
    } finally {
      _syncing = false;
    }
    return false;
  }

  /// 从云端恢复最新一份备份
  Future<bool> restoreFromCloud() async {
    if (_syncing) return false;
    final client = _webdavClient();
    if (client == null) {
      _setWebdavStatus('请先在 WebDav 配置中填写服务器信息');
      return false;
    }
    _syncing = true;
    _setWebdavStatus('正在从云端恢复…');
    try {
      final list = await client.listBackups();
      String? target;
      if (list.contains(cloudBackupName)) {
        target = cloudBackupName; // 固定文件优先（当前数据只有这一份）
      } else if (list.isNotEmpty) {
        target = list.first; // 兼容旧版带时间戳的备份
      }
      if (target == null) {
        _setWebdavStatus('云端还没有备份文件');
        return false;
      }
      final raw = await client.download(target);
      final ok = importJson(raw);
      _setWebdavStatus(ok ? '已恢复云端备份 $target' : '云端备份文件格式不正确');
      return ok;
    } on WebDavException catch (e) {
      _setWebdavStatus(e.message);
    } catch (e) {
      _setWebdavStatus('恢复失败：$e');
    } finally {
      _syncing = false;
    }
    return false;
  }

  /// WebDAV 配置弹窗里"测试连接"
  Future<void> testWebdavConnection() async {
    final client = _webdavClient();
    if (client == null) {
      throw const WebDavException('请填写服务器 URL 和账号');
    }
    await client.testConnection();
  }

  /// 启动时自动同步（多设备切换场景）：
  /// 拉取云端备份并比对 exportedAt 与本地最后变更时间——
  /// 云端更新则恢复云端数据，本地更新则把本地数据推上去。
  Future<void> syncOnLaunch() async {
    if (_syncing) return;
    if (!settings.webdavOn || !settings.webdavAutoSync || !settings.webdavConfigured) return;
    final client = _webdavClient();
    if (client == null) return;
    _syncing = true;
    try {
      final list = await client.listBackups();
      String? target;
      if (list.contains(cloudBackupName)) {
        target = cloudBackupName;
      } else if (list.isNotEmpty) {
        target = list.first;
      }
      if (target == null) {
        _syncing = false;
        await uploadToCloud(auto: true);
        return;
      }
      final raw = await client.download(target);
      final remoteTs = _exportedAtOf(raw);
      if (remoteTs > 0 && remoteTs > _lastChangeTs + 2000) {
        final ok = importJson(raw);
        _setWebdavStatus(ok ? '启动同步：已拉取云端最新数据' : '启动同步：云端备份格式不正确');
      } else {
        // 本地不比云端旧（或云端时间不可读）：以本地为准推上去
        _syncing = false;
        await uploadToCloud(auto: true);
        return;
      }
    } catch (e) {
      _setWebdavStatus('启动同步失败：$e');
    } finally {
      _syncing = false;
    }
  }

  int _exportedAtOf(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final t = DateTime.tryParse((j['exportedAt'] as String?) ?? '');
      return t?.millisecondsSinceEpoch ?? 0;
    } catch (_) {
      return 0;
    }
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

  /// 按任务的专注时长
  /// - day != null：只统计该单日
  /// - 否则 last7=true 只统计近 7 天，false 统计全部
  /// 返回 (任务, 名称, 专注分钟, 番茄数, 超时分钟)——超时分钟来自到时后的负计时
  List<(Task?, String, int, int, int)> taskFocusStats({required bool last7, DateTime? day}) {
    final since = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final dayKey = day == null ? null : _dayOf(day.millisecondsSinceEpoch);
    final byName = <String, (int, int, int, String?)>{}; // name -> (sec, count, overtimeSec, taskId)
    for (final r in records) {
      if (dayKey != null) {
        if (_dayOf(r.startTs) != dayKey) continue;
      } else if (last7 && r.startTs < since) {
        continue;
      }
      final cur = byName[r.taskName] ?? (0, 0, 0, r.taskId);
      byName[r.taskName] = (cur.$1 + r.focusSec, cur.$2 + 1, cur.$3 + r.overtimeSec, r.taskId);
    }
    final list = byName.entries
        .map((e) => (
              tasks.where((t) => t.id == e.value.$4).firstOrNull,
              e.key,
              e.value.$1 ~/ 60,
              e.value.$2,
              e.value.$3 ~/ 60,
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
        'cycleDone': cycleDone,
        'lastChangeTs': _lastChangeTs,
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
      // 周期计数：新版备份直接读取；旧备份回退到会话里的 cycleDone
      final sessionJson = j['session'] as Map<String, dynamic>?;
      cycleDone = (j['cycleDone'] as num?)?.toInt() ??
          (sessionJson?['cycleDone'] as num?)?.toInt() ??
          0;
      _saveTasks();
      _saveRecords();
      _saveSettings();
      _saveCycle();
      _saveSession();
      // 以备份里的"最后变更时间"为准，避免刚恢复就被判成本地更新
      final remoteChange = (j['lastChangeTs'] as num?)?.toInt();
      if (remoteChange != null) {
        _lastChangeTs = remoteChange;
        _prefs.setInt(_kLastChange, _lastChangeTs);
      }
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

  // ---------- 提示音 ----------
  /// 到时系统通知（安卓通知栏 / Windows 托盘气泡）
  void _notifyDone({required String title, required String body}) {
    if (!settings.notifyOn) return;
    unawaited(SystemNotify.show(title: title, body: body));
  }

  /// 到时震动提醒（仅安卓，震动三短一长节奏由原生层定义）
  void _vibrate() {
    if (!settings.vibrateOn) return;
    ScreenKeepOn.vibrate();
  }

  /// 到时铃声（运行时生成 WAV"叮—咚"）
  Future<void> _playBell() async {
    if (!settings.soundOn) return;
    try {
      await _ensureSounds();
      await _bellPlayer.setVolume(settings.volume);
      await _bellPlayer.stop();
      await _bellPlayer.play(DeviceFileSource(_bellPath!));
    } catch (_) {}
  }

  /// 专注倒计时"咔咔"声（assets/sounds/tick.wav）
  Future<void> _playTick() async {
    if (!settings.soundOn) return;
    try {
      await _tickPlayer.setVolume(settings.volume);
      await _tickPlayer.stop();
      await _tickPlayer.play(AssetSource(_tickAsset));
    } catch (_) {}
  }

  /// 设置里试听"咔咔"声
  Future<void> previewTick() => _playTick();

  Future<void> _ensureSounds() async {
    if (_bellPath != null) return;
    final dir = await getTemporaryDirectory();
    final bell = File('${dir.path}${Platform.pathSeparator}tomato_bell.wav');
    if (!await bell.exists()) await bell.writeAsBytes(_buildWav(_bellSamples()));
    _bellPath = bell.path;
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

  @override
  void dispose() {
    _ticker?.cancel();
    _bellPlayer.dispose();
    _tickPlayer.dispose();
    super.dispose();
  }
}
