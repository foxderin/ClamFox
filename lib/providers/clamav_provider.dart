import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/engines/chkrootkit_engine.dart';
import '../data/engines/clamav_engine.dart';
import '../data/engines/rkhunter_engine.dart';
import '../data/engines/scan_engine.dart';
import '../data/scan_history_repository.dart';
import '../models/scan_result.dart';
import '../models/scan_session.dart';
import '../models/scan_settings.dart';
import '../services/polkit_policy.dart';
import '../services/polkit_service.dart';
import '../services/privileged_client.dart';

enum DatabaseStatus { unknown, absent, installed }

class EngineScanSnapshot {
  final String engineId;
  final String engineName;
  final bool isScanning;
  final double? progress;
  final String currentPath;
  final int filesScanned;
  final int threatsFound;
  final List<ScanResult> results;
  final List<String> logs;
  final String? error;

  const EngineScanSnapshot({
    required this.engineId,
    required this.engineName,
    required this.isScanning,
    required this.progress,
    required this.currentPath,
    required this.filesScanned,
    required this.threatsFound,
    required this.results,
    required this.logs,
    this.error,
  });
}

class _EngineRunState {
  final bool isScanning;
  final double? progress;
  final String currentPath;
  final int filesScanned;
  final int threatsFound;
  final List<ScanResult> results;
  final List<String> logs;
  final DateTime? startedAt;
  final bool cancelRequested;
  final String? error;
  final bool logsTruncated;

  const _EngineRunState({
    this.isScanning = false,
    this.progress,
    this.currentPath = '',
    this.filesScanned = 0,
    this.threatsFound = 0,
    this.results = const [],
    this.logs = const [],
    this.startedAt,
    this.cancelRequested = false,
    this.error,
    this.logsTruncated = false,
  });

  _EngineRunState copyWith({
    bool? isScanning,
    double? progress,
    bool clearProgress = false,
    String? currentPath,
    int? filesScanned,
    int? threatsFound,
    List<ScanResult>? results,
    List<String>? logs,
    DateTime? startedAt,
    bool clearStartedAt = false,
    bool? cancelRequested,
    String? error,
    bool clearError = false,
    bool? logsTruncated,
  }) {
    return _EngineRunState(
      isScanning: isScanning ?? this.isScanning,
      progress: clearProgress ? null : (progress ?? this.progress),
      currentPath: currentPath ?? this.currentPath,
      filesScanned: filesScanned ?? this.filesScanned,
      threatsFound: threatsFound ?? this.threatsFound,
      results: results ?? this.results,
      logs: logs ?? this.logs,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      cancelRequested: cancelRequested ?? this.cancelRequested,
      error: clearError ? null : (error ?? this.error),
      logsTruncated: logsTruncated ?? this.logsTruncated,
    );
  }
}

class ClamAvProvider with ChangeNotifier {
  static const int _maxLogLinesPerEngine = 10000;
  static const String _logTruncatedMarker = '…日志过长，后续内容已省略…';

  // ---- ClamAV-specific state ----
  bool _isInstalled = false;
  bool _isUpdating = false;
  String _version = '';
  String _databaseVersion = '';
  DatabaseStatus _databaseStatus = DatabaseStatus.unknown;

  // ---- Generic scan state ----
  final Map<String, _EngineRunState> _engineRunStates = {};
  final Map<String, StreamSubscription<ScanEvent>> _scanSubs = {};
  ScanSettings _scanSettings = const ScanSettings();
  String? _lastError;
  String? _quarantineDir;

  // ---- Scan history ----
  final ScanHistoryRepository _historyRepo = ScanHistoryRepository();
  List<ScanSession> _sessions = const [];

  // ---- Engines ----
  late final Map<String, ScanEngine> _engines = {
    'clamav': ClamAvEngine(
      settingsProvider: () => _scanSettings,
      quarantineDirProvider: () => _quarantineDir ?? '/tmp/clamfox-quarantine',
    ),
    'rkhunter': RkhunterEngine(polkit: _polkitService),
    'chkrootkit': ChkrootkitEngine(polkit: _polkitService),
  };
  final Map<String, EngineAvailability> _engineAvailability = {};
  String _activeEngineId = 'clamav';

  // ---- Throttled notifyListeners ----
  Timer? _notifyThrottle;
  bool _pendingNotify = false;

  // ---- Persistence keys ----
  static const _kScanSettingsKey = 'scan_settings';
  static const _kActiveEngineKey = 'active_engine';
  static const _kPrivilegedModeKey = 'privileged_mode_enabled';

  final PolkitService _polkitService = PolkitService();

  // ---- Privileged helper ----
  final PrivilegedClient _helper = PrivilegedClient();
  final Map<String, String> _helperStreamIds = {};
  bool _helperStarting = false;
  bool _helperInstalling = false;

  // ---- Getters ----
  bool get isInstalled => _isInstalled;
  bool get hasAnyEngineInstalled =>
      _engineAvailability.values.any(
        (availability) => availability.installed,
      ) ||
      _isInstalled;
  bool get isScanning =>
      _engineRunStates.values.any((state) => state.isScanning);
  bool get isUpdating => _isUpdating;
  String get version => _version;
  String get databaseVersion => _databaseVersion;
  DatabaseStatus get databaseStatus => _databaseStatus;
  List<ScanResult> get scanResults => List.unmodifiable(
    _engineRunStates.values.expand((state) => state.results),
  );
  List<String> get scanLogs => List.unmodifiable(
    _engineRunStates.entries.expand((entry) {
      final engineName = _engines[entry.key]?.displayName ?? entry.key;
      return entry.value.logs.map((line) => '[$engineName] $line');
    }),
  );
  ScanSettings get scanSettings => _scanSettings;
  double? get scanProgress {
    final running = _engineRunStates.values.where((state) => state.isScanning);
    if (running.isEmpty) return null;
    final values = running.map((state) => state.progress).whereType<double>();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  String get currentScanPath {
    final running = _engineRunStates.values.where((state) => state.isScanning);
    if (running.isEmpty) return '';
    final paths = running.map((state) => state.currentPath).toSet();
    return paths.length == 1 ? paths.first : '多引擎并行扫描';
  }

  int get threatsFound => _engineRunStates.values.fold(
    0,
    (total, state) => total + state.threatsFound,
  );
  int get filesScanned => _engineRunStates.values.fold(
    0,
    (total, state) => total + state.filesScanned,
  );
  String? get lastError => _lastError;

  bool get privilegedModeEnabled => _helper.isReady;
  bool get privilegedModeStarting => _helperStarting;
  bool get privilegedHelperInstalling => _helperInstalling;
  String? get privilegedHelperError => _helper.lastError;

  /// `true` when `/usr/lib/clamfox/clamfox-helper` exists. Used by the
  /// settings UI to decide whether to show the "install helper" button or
  /// the "enable" toggle.
  bool get privilegedHelperInstalled =>
      File(PrivilegedClient.defaultBinaryPath).existsSync();

  /// Path to the helper binary shipped inside the application bundle —
  /// `flutter build linux` copies it next to the main `clamfox` executable.
  /// Returns null when running in the test isolate (where resolvedExecutable
  /// points at flutter_tester rather than the app bundle).
  String? get bundledHelperPath {
    final exe = Platform.resolvedExecutable;
    if (!exe.endsWith('/clamfox')) return null;
    final candidate = '${File(exe).parent.path}/clamfox-helper';
    return File(candidate).existsSync() ? candidate : null;
  }

  String get activeEngineId => _activeEngineId;
  ScanEngine get activeEngine => _engines[_activeEngineId]!;
  List<ScanEngine> get allEngines => _engines.values.toList(growable: false);
  EngineAvailability availabilityOf(String id) =>
      _engineAvailability[id] ?? EngineAvailability.missing;
  bool isEngineInstalled(String id) => availabilityOf(id).installed;
  String engineVersionText(String id) {
    final availability = availabilityOf(id);
    if (!availability.installed) return '未安装';
    return availability.version ?? '已安装';
  }

  bool engineSupportsUpdateFor(String id) => id == 'clamav' || id == 'rkhunter';

  String engineDatabaseText(String id) => switch (id) {
    'clamav' => _databaseVersion.isEmpty ? '未知' : _databaseVersion,
    'rkhunter' => '可更新数据并刷新文件属性基线',
    'chkrootkit' => '内置规则，无远程数据库',
    _ => '未知',
  };

  List<EngineScanSnapshot> get engineScanSnapshots => _engines.values
      .map((engine) {
        final state = _engineRunStates[engine.id] ?? const _EngineRunState();
        return EngineScanSnapshot(
          engineId: engine.id,
          engineName: engine.displayName,
          isScanning: state.isScanning,
          progress: state.progress,
          currentPath: state.currentPath,
          filesScanned: state.filesScanned,
          threatsFound: state.threatsFound,
          results: List.unmodifiable(state.results),
          logs: List.unmodifiable(state.logs),
          error: state.error,
        );
      })
      .toList(growable: false);

  List<ScanSession> get sessions => List.unmodifiable(_sessions);
  ScanSession? get lastSession => _sessions.isEmpty ? null : _sessions.last;

  ClamAvProvider() {
    unawaited(_loadScanSettings());
    unawaited(_loadActiveEngine());
    unawaited(_loadHistory());
    if (Platform.environment['FLUTTER_TEST'] != 'true') {
      unawaited(checkClamAvInstallation());
      unawaited(_initializePolkit());
      unawaited(refreshEngineAvailability());
      unawaited(_maybeAutoStartPrivilegedMode());
    }
    _helper.addListener(_onHelperStateChanged);
  }

  void _onHelperStateChanged() {
    // Mirror helper state changes (e.g. unexpected disconnect) to listeners
    // so the settings page toggle and engine cards update immediately.
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    _sessions = await _historyRepo.loadAll();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _historyRepo.clear();
    _sessions = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _notifyThrottle?.cancel();
    for (final sub in _scanSubs.values) {
      sub.cancel();
    }
    for (final engine in _engines.values) {
      engine.cancel();
    }
    _helper.removeListener(_onHelperStateChanged);
    unawaited(_helper.stop());
    super.dispose();
  }

  // ---- Errors ----
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  void _setError(String message) {
    _lastError = message;
    notifyListeners();
  }

  void _scheduleNotify() {
    _pendingNotify = true;
    _notifyThrottle ??= Timer(const Duration(milliseconds: 200), () {
      _notifyThrottle = null;
      if (_pendingNotify) {
        _pendingNotify = false;
        notifyListeners();
      }
    });
  }

  // ---- Persistence ----
  Future<void> _loadScanSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kScanSettingsKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _scanSettings = ScanSettings.fromJson(json);
      notifyListeners();
    } catch (e) {
      debugPrint('加载扫描设置失败: $e');
    }
  }

  Future<void> _saveScanSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kScanSettingsKey,
        jsonEncode(_scanSettings.toJson()),
      );
    } catch (e) {
      debugPrint('保存扫描设置失败: $e');
    }
  }

  Future<void> _loadActiveEngine() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kActiveEngineKey);
      if (id != null && _engines.containsKey(id)) {
        _activeEngineId = id;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载活动引擎失败: $e');
    }
  }

  Future<void> setActiveEngine(String id) async {
    if (!_engines.containsKey(id) || id == _activeEngineId) return;
    if (isScanning) {
      _setError('请先停止当前扫描再切换引擎');
      return;
    }
    _activeEngineId = id;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveEngineKey, id);
    } catch (e) {
      debugPrint('保存活动引擎失败: $e');
    }
  }

  void updateScanSettings(ScanSettings settings) {
    _scanSettings = settings;
    notifyListeners();
    unawaited(_saveScanSettings());
  }

  // ---- System authorization ----
  Future<void> _initializePolkit() async {
    try {
      await _polkitService.initialize();
    } catch (e) {
      debugPrint('系统授权服务初始化失败: $e');
    }
  }

  // ---- Engine availability ----
  Future<void> refreshEngineAvailability() async {
    for (final engine in _engines.values) {
      _engineAvailability[engine.id] = await _detectEngine(engine);
    }
    notifyListeners();
  }

  Future<EngineAvailability> _detectEngine(ScanEngine engine) async {
    if (_helper.isReady) {
      try {
        final reply = await _helper.request('detect', {'engine': engine.id});
        if (reply['ok'] == true) {
          final data = reply['data'] as Map<String, dynamic>?;
          if (data != null) {
            final installed = data['installed'] == true;
            return EngineAvailability(
              installed: installed,
              version: data['version']?.toString(),
              hint: data['hint']?.toString(),
            );
          }
        }
      } catch (e) {
        debugPrint('helper detect ${engine.id} 失败: $e');
        // Fall through to direct probe.
      }
    }
    try {
      return await engine.checkAvailability();
    } catch (_) {
      return EngineAvailability.missing;
    }
  }

  // ---- Privileged mode ----
  Future<bool> enablePrivilegedMode() async {
    if (_helper.isReady || _helperStarting) return _helper.isReady;
    _helperStarting = true;
    notifyListeners();
    try {
      final ok = await _helper.start();
      if (!ok) {
        _setError(_helper.lastError ?? '特权模式启动失败');
        return false;
      }
      await _savePrivilegedModeFlag(true);
      await refreshEngineAvailability();
      return true;
    } finally {
      _helperStarting = false;
      notifyListeners();
    }
  }

  Future<void> disablePrivilegedMode() async {
    if (!_helper.isReady) {
      await _savePrivilegedModeFlag(false);
      return;
    }
    if (isScanning) {
      _setError('请先停止当前扫描再关闭特权模式');
      return;
    }
    await _helper.stop();
    await _savePrivilegedModeFlag(false);
    await refreshEngineAvailability();
  }

  Future<void> _maybeAutoStartPrivilegedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kPrivilegedModeKey) != true) return;
    } catch (_) {
      return;
    }
    // Silent best-effort restart. Failures (auth denied, helper missing) are
    // logged via _helper.lastError; we don't pop a dialog at startup.
    final ok = await _helper.start();
    if (ok) await refreshEngineAvailability();
  }

  Future<void> _savePrivilegedModeFlag(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrivilegedModeKey, enabled);
    } catch (e) {
      debugPrint('保存特权模式状态失败: $e');
    }
  }

  /// One-click install: copy the helper binary shipped inside the app bundle
  /// into `/usr/lib/clamfox/` and write the system authorization policy to its system path.
  /// Both copies happen inside a single `pkexec sh -c ...` so the user only
  /// sees one auth prompt.
  Future<bool> installPrivilegedHelper() async {
    if (_helperInstalling) return false;
    final src = bundledHelperPath;
    if (src == null) {
      _setError('应用 bundle 中未找到特权模式服务（请用 flutter build 重新构建）');
      return false;
    }
    _helperInstalling = true;
    notifyListeners();
    final policyTmp =
        '/tmp/clamfox-policy-${DateTime.now().microsecondsSinceEpoch}.policy';
    try {
      try {
        await File(policyTmp).writeAsString(buildClamfoxPolkitPolicy());
      } catch (e) {
        _setError('无法写入临时系统授权策略: $e');
        return false;
      }

      final shellScript =
          'set -e && '
          'install -d -m 755 /usr/lib/clamfox && '
          'install -m 755 ${_shellQuote(src)} ${_shellQuote(PrivilegedClient.defaultBinaryPath)} && '
          'install -m 644 ${_shellQuote(policyTmp)} ${_shellQuote(kClamfoxPolicyFilePath)}';

      final code = await _runPrivileged('sh', ['-c', shellScript]);
      if (code != 0) {
        _setError('特权模式服务安装失败（退出码 $code）');
        return false;
      }
      _lastError = null;
      notifyListeners();
      return true;
    } finally {
      try {
        await File(policyTmp).delete();
      } catch (_) {}
      _helperInstalling = false;
      notifyListeners();
    }
  }

  /// One-click uninstall: stop the running helper if any, then remove the
  /// installed binary, its `/usr/lib/clamfox/` directory, and the system authorization
  /// policy file in a single `pkexec sh -c ...` so the user sees at most one
  /// auth prompt. Also clears the persisted privileged-mode preference.
  Future<bool> uninstallPrivilegedHelper() async {
    if (_helperInstalling) return false;
    if (isScanning) {
      _setError('请先停止当前扫描再卸载特权模式服务');
      return false;
    }
    _helperInstalling = true;
    notifyListeners();
    try {
      // Stop the running helper first; otherwise the binary on disk may be
      // held open and removal silently leaves stale state.
      if (_helper.isReady) {
        await _helper.stop();
      }

      final shellScript =
          'set -e && '
          'rm -f ${_shellQuote(PrivilegedClient.defaultBinaryPath)} && '
          'rm -f ${_shellQuote(kClamfoxPolicyFilePath)} && '
          'rmdir --ignore-fail-on-non-empty /usr/lib/clamfox 2>/dev/null || true';

      final code = await _runPrivileged('sh', ['-c', shellScript]);
      if (code != 0) {
        _setError('特权模式服务卸载失败（退出码 $code）');
        return false;
      }
      await _savePrivilegedModeFlag(false);
      await refreshEngineAvailability();
      _lastError = null;
      notifyListeners();
      return true;
    } finally {
      _helperInstalling = false;
      notifyListeners();
    }
  }

  /// Single-quote a path for `sh -c` consumption, escaping any embedded
  /// single quotes. Defensive — bundled paths shouldn't contain quotes, but
  /// a user-installed app at `/home/me's app/...` would otherwise break.
  String _shellQuote(String value) {
    final escaped = value.replaceAll("'", r"'\''");
    return "'$escaped'";
  }

  // ---- ClamAV install / DB check ----
  Future<void> checkClamAvInstallation() async {
    try {
      final result = await Process.run('clamscan', ['--version']);
      if (result.exitCode == 0) {
        _isInstalled = true;
        _version = result.stdout.toString().trim();
        await _getDatabaseVersion();
      } else {
        _isInstalled = false;
      }
    } catch (e) {
      _isInstalled = false;
      debugPrint('ClamAV not found: $e');
    }
    notifyListeners();
  }

  Future<void> _getDatabaseVersion() async {
    try {
      const dbPaths = [
        '/var/lib/clamav',
        '/usr/share/clamav',
        '/opt/clamav/share/clamav',
      ];
      String? dbDir;
      for (final path in dbPaths) {
        final dir = Directory(path);
        if (await dir.exists()) {
          final files = await dir.list().toList();
          if (files.any(
            (f) => f.path.endsWith('.cvd') || f.path.endsWith('.cld'),
          )) {
            dbDir = path;
            break;
          }
        }
      }

      if (dbDir == null) {
        _databaseStatus = DatabaseStatus.absent;
        _databaseVersion = '未安装';
        return;
      }

      _databaseStatus = DatabaseStatus.installed;
      final mainCvd = p.join(dbDir, 'main.cvd');
      final mainCld = p.join(dbDir, 'main.cld');
      final target = await File(mainCvd).exists()
          ? mainCvd
          : (await File(mainCld).exists() ? mainCld : null);
      if (target == null) {
        _databaseVersion = '已安装';
        return;
      }
      final result = await Process.run('sigtool', ['--info', target]);
      if (result.exitCode == 0) {
        final m = RegExp(
          r'Version:\s*(\d+)',
        ).firstMatch(result.stdout.toString());
        _databaseVersion = m?.group(1) ?? '已安装';
      } else {
        _databaseVersion = '已安装';
      }
    } catch (e) {
      _databaseStatus = DatabaseStatus.unknown;
      _databaseVersion = '未知';
      debugPrint('Error getting database version: $e');
    }
  }

  // ---- DB / signature update (engine-aware) ----
  bool get engineSupportsUpdate => engineSupportsUpdateFor(_activeEngineId);

  Future<void> updateDatabase({String? engineId}) async {
    final id = engineId ?? _activeEngineId;
    final engine = _engines[id];
    if (_isUpdating || engine == null) return;
    if (!engineSupportsUpdateFor(id)) {
      _setError('${engine.displayName} 不需要数据库更新');
      return;
    }
    _isUpdating = true;
    _lastError = null;
    notifyListeners();

    try {
      int? exitCode;
      if (_helper.isReady) {
        exitCode = await _runHelperJob('update', {
          'engine': id,
        }, logTag: '$id update');
        if (exitCode == 0 && id == 'clamav') {
          await _getDatabaseVersion();
        }
      } else {
        switch (id) {
          case 'clamav':
            exitCode = await _runPrivileged('freshclam', [
              '--verbose',
              '--stdout',
            ]);
            if (exitCode == 0) await _getDatabaseVersion();
          case 'rkhunter':
            exitCode = await _runPrivileged('rkhunter', [
              '--update',
              '--nocolors',
            ]);
            if (exitCode == 0) {
              await _runPrivileged('rkhunter', ['--propupd', '--nocolors']);
            }
          default:
            exitCode = 0;
        }
      }
      if (exitCode != 0) {
        _setError('${engine.displayName} 数据库更新失败（退出码 ${exitCode ?? '未知'}）');
      }
    } on Exception catch (e) {
      _setError('数据库更新异常: $e');
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<int> _runPrivileged(String executable, List<String> args) async {
    final polkitAvailable = await PolkitService.isPolkitAvailable();
    final Process process = polkitAvailable
        ? await _polkitService.startPrivilegedProcess(executable, args)
        : await Process.start('sudo', [executable, ...args]);
    process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((d) => debugPrint('[$executable] $d'));
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((d) => debugPrint('[$executable err] $d'));
    return process.exitCode;
  }

  Future<int?> _runHelperJob(
    String type,
    Map<String, dynamic> args, {
    String? logTag,
  }) async {
    final tag = logTag ?? type;
    final result = _helper.openStream(type, args);
    int? exitCode;
    try {
      await for (final msg in result.stream) {
        switch (msg['event']?.toString()) {
          case 'log':
            debugPrint('[helper $tag] ${msg['message']}');
          case 'error':
            _setError(msg['message']?.toString() ?? '$tag 失败');
          case 'finished':
            final code = msg['exitCode'];
            exitCode = code is int ? code : null;
        }
      }
    } catch (e) {
      _setError('$tag 通信异常: $e');
    }
    return exitCode;
  }

  // ---- Scan: dispatch to one or more engines ----
  Future<void> scanPath(String path) async {
    await scanWithEngines(path, {_activeEngineId});
  }

  Future<void> scanWithEngines(String path, Set<String> engineIds) async {
    if (isScanning) return;
    final selected = engineIds
        .where((id) => _engines.containsKey(id) && isEngineInstalled(id))
        .toSet();
    if (selected.isEmpty) {
      _setError('请先选择至少一个已安装的扫描引擎');
      return;
    }

    final runnable = <ScanEngine>[];
    for (final id in selected) {
      final engine = _engines[id]!;
      if (engine.id == 'clamav' &&
          _databaseStatus != DatabaseStatus.installed) {
        _setError('ClamAV 病毒库未安装，请先更新病毒数据库');
        continue;
      }
      if (engine.supportsPathScan) {
        final exists = Directory(path).existsSync() || File(path).existsSync();
        if (!exists) {
          _setError('扫描路径不存在: $path');
          continue;
        }
      }
      runnable.add(engine);
    }

    if (runnable.isEmpty) return;

    _engineRunStates.clear();
    _helperStreamIds.clear();
    _lastError = null;
    final startedAt = DateTime.now();
    for (final engine in runnable) {
      _engineRunStates[engine.id] = _EngineRunState(
        isScanning: true,
        currentPath: engine.supportsPathScan ? path : '系统级扫描',
        startedAt: startedAt,
      );
    }
    notifyListeners();

    await _ensureQuarantineDir();

    for (final engine in runnable) {
      try {
        final source = _scanEventStreamFor(engine, path);
        if (source.helperId != null) {
          _helperStreamIds[engine.id] = source.helperId!;
        }
        _scanSubs[engine.id] = source.events.listen(
          (event) => _handleScanEvent(engine.id, event),
          onError: (Object e) =>
              _finishEngineScan(engine.id, error: '扫描错误: $e'),
          onDone: () => _finishEngineScan(engine.id),
        );
      } on Exception catch (e) {
        await _finishEngineScan(engine.id, error: '扫描启动失败: $e');
      }
    }
  }

  ({Stream<ScanEvent> events, String? helperId}) _scanEventStreamFor(
    ScanEngine engine,
    String path,
  ) {
    if (_helper.isReady) {
      final args = <String, dynamic>{'engine': engine.id};
      if (engine.id == 'clamav') {
        args['path'] = path;
        args['settings'] = _scanSettings.toJson();
        args['quarantineDir'] = _quarantineDir ?? '/tmp/clamfox-quarantine';
      }
      final result = _helper.openStream('scan', args);
      return (
        events: _helperEventsToScanEvents(result.stream, engine.id),
        helperId: result.id,
      );
    }
    return (
      events: engine.scan(path: engine.supportsPathScan ? path : null),
      helperId: null,
    );
  }

  Stream<ScanEvent> _helperEventsToScanEvents(
    Stream<Map<String, dynamic>> raw,
    String engineId,
  ) async* {
    await for (final msg in raw) {
      final event = msg['event']?.toString();
      switch (event) {
        case 'started':
          yield ScanStarted(path: msg['path']?.toString());
        case 'progress':
          final total = msg['totalScanned'];
          final inc = msg['incrementalScanned'];
          yield ScanFileProgress(
            totalScanned: total is num ? total.toInt() : null,
            incrementalScanned: inc is num ? inc.toInt() : 0,
          );
        case 'threat':
          yield ScanThreatFound(
            ScanResult(
              filePath: msg['filePath']?.toString() ?? '',
              threatName: msg['threatName']?.toString() ?? '',
              timestamp: DateTime.now(),
              action: ScanAction.detected,
              engine: engineId,
              details: msg['details']?.toString(),
            ),
          );
        case 'log':
          yield ScanLog(msg['message']?.toString() ?? '');
        case 'error':
          yield ScanFailed(message: msg['message']?.toString() ?? '特权模式服务返回错误');
        case 'finished':
          final code = msg['exitCode'];
          final exitCode = code is int ? code : null;
          if (msg['ok'] == false) {
            yield ScanFailed(message: _scanFailureMessage(engineId, exitCode));
          }
          yield ScanFinished(exitCode: exitCode);
      }
    }
  }

  String _scanFailureMessage(String engineId, int? exitCode) {
    final name = _engines[engineId]?.displayName ?? engineId;
    final code = exitCode == null ? '未知' : exitCode.toString();
    return '$name 扫描失败（退出码 $code）';
  }

  void _handleScanEvent(String engineId, ScanEvent event) {
    final state = _engineRunStates[engineId] ?? const _EngineRunState();
    switch (event) {
      case ScanStarted():
        break;
      case ScanFileProgress(:final totalScanned, :final incrementalScanned):
        _engineRunStates[engineId] = state.copyWith(
          filesScanned: totalScanned ?? state.filesScanned + incrementalScanned,
        );
        _scheduleNotify();
      case ScanThreatFound(:final result):
        _engineRunStates[engineId] = state.copyWith(
          results: [...state.results, result],
          threatsFound: state.threatsFound + 1,
        );
        _scheduleNotify();
      case ScanLog(:final message):
        final (logs, truncated) = _appendLogLines(state, message);
        _engineRunStates[engineId] = state.copyWith(
          logs: logs,
          logsTruncated: truncated,
        );
        _scheduleNotify();
      case ScanFailed(:final message):
        unawaited(_finishEngineScan(engineId, error: message));
      case ScanFinished():
        break;
    }
  }

  (List<String>, bool) _appendLogLines(_EngineRunState state, String message) {
    if (message.trim().isEmpty) return (state.logs, state.logsTruncated);
    final next = List<String>.of(state.logs);
    var truncated = state.logsTruncated;
    for (final raw in const LineSplitter().convert(message)) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      if (next.length < _maxLogLinesPerEngine) {
        next.add(line);
        continue;
      }
      if (!truncated) {
        next.add(_logTruncatedMarker);
        truncated = true;
      }
      break;
    }
    return (next, truncated);
  }

  Future<void> _finishEngineScan(String engineId, {String? error}) async {
    final state = _engineRunStates[engineId];
    if (state == null || !state.isScanning) return;
    if (error != null) _lastError = error;
    final completed = state.copyWith(
      isScanning: false,
      progress: 1.0,
      error: error,
    );
    _engineRunStates[engineId] = completed;
    await _scanSubs.remove(engineId)?.cancel();
    _helperStreamIds.remove(engineId);
    await _persistEngineSession(engineId, completed);
    notifyListeners();
  }

  Future<void> cancelScan() async {
    if (!isScanning) return;
    for (final entry in _engineRunStates.entries.toList()) {
      if (entry.value.isScanning) {
        _engineRunStates[entry.key] = entry.value.copyWith(
          cancelRequested: true,
        );
      }
    }
    if (_helper.isReady && _helperStreamIds.isNotEmpty) {
      await Future.wait(_helperStreamIds.values.map(_helper.cancelStream));
    }
    await Future.wait(_engines.values.map((engine) => engine.cancel()));
  }

  Future<void> _persistEngineSession(
    String engineId,
    _EngineRunState state,
  ) async {
    final start = state.startedAt;
    if (start == null) return;
    final session = ScanSession(
      id: '${start.toIso8601String()}-$engineId',
      startedAt: start,
      finishedAt: DateTime.now(),
      engine: engineId,
      target: state.currentPath,
      filesScanned: state.filesScanned,
      threatsFound: state.threatsFound,
      results: List.unmodifiable(state.results),
      logs: List.unmodifiable(state.logs),
      cancelled: state.cancelRequested,
    );
    _sessions = [..._sessions, session];
    while (_sessions.length > ScanHistoryRepository.maxSessions) {
      _sessions = _sessions.sublist(1);
    }
    await _historyRepo.append(session);
  }

  void clearScanResults() {
    _engineRunStates.clear();
    notifyListeners();
  }

  // ---- Quarantine ----
  Future<String> _ensureQuarantineDir() async {
    if (_quarantineDir != null) return _quarantineDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'quarantine'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      try {
        await Process.run('chmod', ['700', dir.path]);
      } catch (_) {}
    }
    _quarantineDir = dir.path;
    return _quarantineDir!;
  }

  Future<String> get quarantineDir async => _ensureQuarantineDir();

  // ---- Threat handling (only meaningful for ClamAV findings) ----
  Future<bool> deleteThreat(ScanResult result) async {
    try {
      final file = File(result.filePath);
      if (_helper.isReady) {
        final reply = await _helper.request('delete', {
          'path': result.filePath,
        });
        if (reply['ok'] != true) {
          _setError('删除文件失败: ${reply['error'] ?? '特权模式服务返回错误'}');
          return false;
        }
      } else if (await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          final code = await _runPrivileged('rm', ['-f', result.filePath]);
          if (code != 0) {
            _setError('删除文件失败（退出码 $code）: ${result.filePath}');
            return false;
          }
        }
      }
      _replaceResult(result, ScanAction.removed);
      return true;
    } catch (e) {
      _setError('删除文件异常: $e');
      return false;
    }
  }

  Future<bool> quarantineThreat(ScanResult result) async {
    try {
      final qdir = await _ensureQuarantineDir();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final dst = p.join(qdir, '$stamp-${p.basename(result.filePath)}');
      final src = File(result.filePath);
      if (!await src.exists()) {
        _setError('文件不存在: ${result.filePath}');
        return false;
      }
      if (_helper.isReady) {
        final reply = await _helper.request('move', {
          'from': result.filePath,
          'to': dst,
        });
        if (reply['ok'] != true) {
          _setError('隔离文件失败: ${reply['error'] ?? '特权模式服务返回错误'}');
          return false;
        }
      } else {
        try {
          await src.rename(dst);
        } on FileSystemException {
          final code = await _runPrivileged('mv', [result.filePath, dst]);
          if (code != 0) {
            _setError('隔离文件失败（退出码 $code）');
            return false;
          }
        }
      }
      _replaceResult(result, ScanAction.quarantined);
      return true;
    } catch (e) {
      _setError('隔离异常: $e');
      return false;
    }
  }

  void ignoreThreat(ScanResult result) {
    for (final entry in _engineRunStates.entries.toList()) {
      final filtered = entry.value.results
          .where(
            (r) =>
                r.filePath != result.filePath ||
                r.timestamp != result.timestamp,
          )
          .toList(growable: false);
      if (filtered.length != entry.value.results.length) {
        _engineRunStates[entry.key] = entry.value.copyWith(
          results: filtered,
          threatsFound: filtered.length,
        );
      }
    }
    notifyListeners();
  }

  void _replaceResult(ScanResult old, ScanAction action) {
    var changed = false;
    for (final entry in _engineRunStates.entries.toList()) {
      final list = [...entry.value.results];
      final i = list.indexWhere(
        (r) => r.filePath == old.filePath && r.timestamp == old.timestamp,
      );
      if (i < 0) continue;
      list[i] = old.copyWith(action: action);
      _engineRunStates[entry.key] = entry.value.copyWith(results: list);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // ---- ClamAV install (cross-distro) ----
  Future<bool> installClamAv() => installEngine('clamav');

  Future<bool> installEngine(String engineId) async {
    final engine = _engines[engineId];
    if (engine == null) return false;
    try {
      int? code;
      if (_helper.isReady) {
        code = await _runHelperJob('install', {
          'engine': engineId,
        }, logTag: '$engineId install');
      } else {
        final pm = await _detectPackageManager(engineId);
        if (pm == null) {
          _setError('未识别的包管理器，请手动安装 ${engine.displayName}');
          return false;
        }
        code = await _runPrivileged(pm.executable, pm.installArgs);
      }
      if (code == 0) {
        await checkClamAvInstallation();
        await refreshEngineAvailability();
        return true;
      }
      _setError('${engine.displayName} 安装失败（退出码 ${code ?? '未知'}）');
      return false;
    } on Exception catch (e) {
      _setError('${engine.displayName} 安装异常: $e');
      return false;
    }
  }

  Future<_PackageManager?> _detectPackageManager(String engineId) async {
    Future<bool> exists(String bin) async {
      final r = await Process.run('which', [bin]);
      return r.exitCode == 0;
    }

    final packages = _enginePackages(engineId);
    if (packages.isEmpty) return null;

    if (await exists('apt')) {
      return _PackageManager(
        name: 'apt',
        executable: 'apt',
        installArgs: ['install', '-y', ...packages.apt],
      );
    }
    if (await exists('pacman')) {
      return _PackageManager(
        name: 'pacman',
        executable: 'pacman',
        installArgs: ['-S', '--noconfirm', ...packages.pacman],
      );
    }
    if (await exists('dnf')) {
      return _PackageManager(
        name: 'dnf',
        executable: 'dnf',
        installArgs: ['install', '-y', ...packages.dnf],
      );
    }
    if (await exists('yum')) {
      return _PackageManager(
        name: 'yum',
        executable: 'yum',
        installArgs: ['install', '-y', ...packages.dnf],
      );
    }
    if (await exists('zypper')) {
      return _PackageManager(
        name: 'zypper',
        executable: 'zypper',
        installArgs: ['install', '-y', ...packages.zypper],
      );
    }
    return null;
  }

  _EnginePackages _enginePackages(String engineId) => switch (engineId) {
    'clamav' => const _EnginePackages(
      apt: ['clamav', 'clamav-daemon', 'clamav-freshclam'],
      pacman: ['clamav'],
      dnf: ['clamav', 'clamav-update'],
      zypper: ['clamav'],
    ),
    'rkhunter' => _EnginePackages.single('rkhunter'),
    'chkrootkit' => _EnginePackages.single('chkrootkit'),
    _ => const _EnginePackages.empty(),
  };
}

class _EnginePackages {
  final List<String> apt;
  final List<String> pacman;
  final List<String> dnf;
  final List<String> zypper;

  const _EnginePackages({
    required this.apt,
    required this.pacman,
    required this.dnf,
    required this.zypper,
  });

  _EnginePackages.single(String packageName)
    : apt = [packageName],
      pacman = [packageName],
      dnf = [packageName],
      zypper = [packageName];

  const _EnginePackages.empty()
    : apt = const [],
      pacman = const [],
      dnf = const [],
      zypper = const [];

  bool get isEmpty =>
      apt.isEmpty && pacman.isEmpty && dnf.isEmpty && zypper.isEmpty;
}

class _PackageManager {
  final String name;
  final String executable;
  final List<String> installArgs;
  const _PackageManager({
    required this.name,
    required this.executable,
    required this.installArgs,
  });
}
