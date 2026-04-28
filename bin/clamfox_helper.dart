// ClamFox 特权助手（root daemon）。
//
// pkexec 一次起本程序，主进程通过 stdio JSON Lines RPC 调用所有需要 root
// 的操作。helper 永不接受任意命令字符串：可执行文件路径与参数都是硬编码
// 模板，外部输入只能是预定义枚举或经严格 schema 校验的值。
//
// 协议：
//   主进程 -> helper:  { "id": "...", "type": "...", ...args }
//   helper -> 主进程:  { "id": "...", "ok": true|false, "data"?, "error"? }
//                      { "id": "...", "event": "started|progress|threat|log|finished|error", ... }
//
// 编译：dart compile exe bin/clamfox_helper.dart -o build/clamfox-helper
// 部署：见 scripts/install_helper.sh

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clamfox/data/clamav/clamscan_output_parser.dart';
import 'package:clamfox/data/engines/engine_commands.dart';
import 'package:clamfox/data/engines/rkhunter_output_parser.dart';
import 'package:clamfox/models/scan_settings.dart';

Future<void> main() async {
  if (!await _isRunningAsRoot()) {
    stderr.writeln('ClamFox 特权模式服务必须以 root 身份运行');
    exit(1);
  }
  await HelperServer().run();
}

Future<bool> _isRunningAsRoot() async {
  try {
    final r = await Process.run('id', ['-u']);
    return r.stdout.toString().trim() == '0';
  } on ProcessException {
    return false;
  }
}

class HelperServer {
  final Map<String, _RunningJob> _jobs = {};
  bool _shutdown = false;

  Future<void> run() async {
    final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    try {
      await for (final line in lines) {
        if (_shutdown) break;
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        Map<String, dynamic> req;
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is! Map) {
            _send({'ok': false, 'error': 'request must be JSON object'});
            continue;
          }
          req = Map<String, dynamic>.from(parsed);
        } on FormatException catch (e) {
          _send({'ok': false, 'error': 'invalid JSON: ${e.message}'});
          continue;
        }
        unawaited(_handle(req));
      }
    } finally {
      await _shutdownAll();
    }
  }

  Future<void> _handle(Map<String, dynamic> req) async {
    final id = req['id']?.toString();
    final type = req['type']?.toString();
    if (id == null || id.isEmpty) {
      _send({'ok': false, 'error': 'missing id'});
      return;
    }
    try {
      switch (type) {
        case 'ping':
          _replyOk(id);
        case 'detect':
          await _handleDetect(id, req);
        case 'scan':
          await _handleScan(id, req);
        case 'update':
          await _handleUpdate(id, req);
        case 'install':
          await _handleInstall(id, req);
        case 'cancel':
          await _handleCancel(id, req);
        case 'delete':
          await _handleDelete(id, req);
        case 'move':
          await _handleMove(id, req);
        case 'shutdown':
          _replyOk(id);
          _shutdown = true;
          await _shutdownAll();
          await stdout.flush();
          exit(0);
        case null:
          _replyError(id, 'missing type');
        default:
          _replyError(id, 'unknown type: $type');
      }
    } catch (e, st) {
      _replyError(id, 'internal: $e');
      stderr.writeln('handler error for $type: $e\n$st');
    }
  }

  // ---- IPC primitives ----

  void _send(Map<String, dynamic> obj) {
    stdout.writeln(jsonEncode(obj));
  }

  void _replyOk(String id, [Map<String, dynamic>? data]) {
    final m = <String, dynamic>{'id': id, 'ok': true};
    if (data != null) m['data'] = data;
    _send(m);
  }

  void _replyError(String id, String msg) {
    _send({'id': id, 'ok': false, 'error': msg});
  }

  void _emit(String id, String event, [Map<String, dynamic>? data]) {
    final m = <String, dynamic>{'id': id, 'event': event};
    if (data != null) m.addAll(data);
    _send(m);
  }

  bool _isSafePath(String? p) {
    if (p == null || p.isEmpty) return false;
    if (!p.startsWith('/')) return false;
    final segments = p.split('/');
    if (segments.contains('..')) return false;
    return true;
  }

  // ---- detect ----

  Future<void> _handleDetect(String id, Map<String, dynamic> req) async {
    final engine = req['engine']?.toString();
    if (!EngineCommands.isValidEngine(engine)) {
      _replyError(id, 'invalid engine');
      return;
    }
    final args = EngineCommands.versionArgs[engine]!;
    String? version;
    bool installed = false;

    try {
      final r = await Process.run(args.first, args.sublist(1));
      final text = (r.stdout.toString() + r.stderr.toString()).trim();
      if (r.exitCode == 0 ||
          (engine == 'chkrootkit' &&
              text.toLowerCase().contains('chkrootkit'))) {
        installed = true;
        if (text.isNotEmpty) version = text.split('\n').first.trim();
      }
    } on ProcessException {
      // fall through to filesystem detection
    }

    if (!installed) {
      for (final p in EngineCommands.binaryPaths[engine] ?? const <String>[]) {
        if (File(p).existsSync()) {
          installed = true;
          break;
        }
      }
    }

    _replyOk(id, {
      'installed': installed,
      'version': version,
      'hint': installed ? null : '请安装 $engine',
    });
  }

  // ---- scan ----

  Future<void> _handleScan(String id, Map<String, dynamic> req) async {
    final engine = req['engine']?.toString();
    if (!EngineCommands.isValidEngine(engine)) {
      _replyError(id, 'invalid engine');
      return;
    }

    Process proc;
    final job = _RunningJob.placeholder();

    try {
      switch (engine) {
        case 'clamav':
          final path = req['path']?.toString();
          if (!_isSafePath(path)) {
            _replyError(id, 'invalid path');
            return;
          }
          final settingsRaw = req['settings'];
          if (settingsRaw is! Map) {
            _replyError(id, 'missing settings');
            return;
          }
          final settings = ScanSettings.fromJson(
            Map<String, dynamic>.from(settingsRaw),
          );
          final quarantineDir = req['quarantineDir']?.toString() ?? '/tmp';
          if (!_isSafePath(quarantineDir)) {
            _replyError(id, 'invalid quarantineDir');
            return;
          }
          final args = EngineCommands.buildClamscanArgs(
            settings: settings,
            path: path!,
            quarantineDir: quarantineDir,
          );
          proc = await Process.start('clamscan', args);
          _emit(id, 'started', {'path': path});
          job.bindClamav(id, proc, _emit);
        case 'rkhunter':
          proc = await Process.start(
            'rkhunter',
            EngineCommands.rkhunterScanArgs,
          );
          _emit(id, 'started');
          job.bindRkhunter(id, proc, _emit);
        case 'chkrootkit':
          proc = await Process.start(
            'chkrootkit',
            EngineCommands.chkrootkitScanArgs,
          );
          _emit(id, 'started');
          job.bindChkrootkit(id, proc, _emit);
        default:
          _replyError(id, 'unsupported engine');
          return;
      }
    } on ProcessException catch (e) {
      _emit(id, 'error', {'message': '$engine 启动失败: ${e.message}'});
      _emit(id, 'finished', {'exitCode': null, 'ok': false});
      return;
    }

    job.proc = proc;
    _jobs[id] = job;

    proc.exitCode.then((code) {
      // clamscan: 0 = clean, 1 = malware found, 2+ = error.
      // rkhunter: 0 = clean, 1 = warnings (non-fatal), 2+ = error.
      final ok = switch (engine) {
        'clamav' => code <= 1,
        'rkhunter' => code <= 1,
        _ => code == 0,
      };
      _emit(id, 'finished', {'exitCode': code, 'ok': ok});
      _jobs.remove(id);
      job.dispose();
    });
  }

  // ---- update ----

  Future<void> _handleUpdate(String id, Map<String, dynamic> req) async {
    final engine = req['engine']?.toString();
    if (!EngineCommands.isValidEngine(engine)) {
      _replyError(id, 'invalid engine');
      return;
    }
    final cmd = EngineCommands.updateCommand[engine];
    if (cmd == null) {
      _replyError(id, '$engine 不支持更新');
      return;
    }
    Process proc;
    try {
      proc = await Process.start(cmd.first, cmd.sublist(1));
    } on ProcessException catch (e) {
      _emit(id, 'error', {'message': '$engine 更新启动失败: ${e.message}'});
      _emit(id, 'finished', {'exitCode': null, 'ok': false});
      return;
    }
    _emit(id, 'started');
    final job = _RunningJob(proc);
    _jobs[id] = job;
    job.bindLogStream(id, proc, _emit);

    proc.exitCode.then((code) {
      _emit(id, 'finished', {'exitCode': code, 'ok': code == 0});
      _jobs.remove(id);
      job.dispose();
    });
  }

  // ---- install ----

  Future<void> _handleInstall(String id, Map<String, dynamic> req) async {
    final engine = req['engine']?.toString();
    if (!EngineCommands.isValidEngine(engine)) {
      _replyError(id, 'invalid engine');
      return;
    }
    final pkgs = EnginePackages.byEngine[engine];
    if (pkgs == null || pkgs.isEmpty) {
      _replyError(id, '$engine 无安装包定义');
      return;
    }
    final pm = await _detectPackageManager();
    if (pm == null) {
      _replyError(id, '未识别的包管理器');
      return;
    }

    Process proc;
    try {
      proc = await Process.start(pm.executable, pm.installArgsFor(pkgs));
    } on ProcessException catch (e) {
      _emit(id, 'error', {'message': '${pm.executable} 启动失败: ${e.message}'});
      _emit(id, 'finished', {'exitCode': null, 'ok': false});
      return;
    }
    _emit(id, 'started', {'packageManager': pm.executable});
    final job = _RunningJob(proc);
    _jobs[id] = job;
    job.bindLogStream(id, proc, _emit);

    proc.exitCode.then((code) {
      _emit(id, 'finished', {'exitCode': code, 'ok': code == 0});
      _jobs.remove(id);
      job.dispose();
    });
  }

  Future<_PackageManager?> _detectPackageManager() async {
    Future<bool> exists(String b) async {
      final r = await Process.run('which', [b]);
      return r.exitCode == 0;
    }

    if (await exists('apt')) return _PackageManager.apt();
    if (await exists('pacman')) return _PackageManager.pacman();
    if (await exists('dnf')) return _PackageManager.dnf();
    if (await exists('yum')) return _PackageManager.yum();
    if (await exists('zypper')) return _PackageManager.zypper();
    return null;
  }

  // ---- cancel ----

  Future<void> _handleCancel(String id, Map<String, dynamic> req) async {
    final scanId = req['scanId']?.toString();
    if (scanId == null || scanId.isEmpty) {
      _replyError(id, 'missing scanId');
      return;
    }
    final job = _jobs[scanId];
    if (job == null || job.proc == null) {
      _replyOk(id, {'note': 'no such job'});
      return;
    }
    job.proc!.kill(ProcessSignal.sigterm);
    Timer(const Duration(seconds: 3), () {
      _jobs[scanId]?.proc?.kill(ProcessSignal.sigkill);
    });
    _replyOk(id);
  }

  // ---- delete / move ----

  Future<void> _handleDelete(String id, Map<String, dynamic> req) async {
    final path = req['path']?.toString();
    if (!_isSafePath(path)) {
      _replyError(id, 'invalid path');
      return;
    }
    try {
      final f = File(path!);
      if (await f.exists()) await f.delete();
      _replyOk(id);
    } on FileSystemException catch (e) {
      _replyError(id, e.message);
    }
  }

  Future<void> _handleMove(String id, Map<String, dynamic> req) async {
    final from = req['from']?.toString();
    final to = req['to']?.toString();
    if (!_isSafePath(from) || !_isSafePath(to)) {
      _replyError(id, 'invalid path');
      return;
    }
    try {
      final src = File(from!);
      if (!await src.exists()) {
        _replyError(id, 'source missing');
        return;
      }
      final dstDir = File(to!).parent;
      if (!await dstDir.exists()) await dstDir.create(recursive: true);
      await src.rename(to);
      _replyOk(id);
    } on FileSystemException catch (e) {
      _replyError(id, e.message);
    }
  }

  // ---- shutdown ----

  Future<void> _shutdownAll() async {
    for (final job in _jobs.values) {
      job.proc?.kill(ProcessSignal.sigterm);
    }
    if (_jobs.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
      for (final job in _jobs.values) {
        job.proc?.kill(ProcessSignal.sigkill);
        job.dispose();
      }
    }
    _jobs.clear();
  }
}

class _RunningJob {
  Process? proc;
  final List<StreamSubscription<dynamic>> subs = [];

  _RunningJob(this.proc);
  _RunningJob.placeholder() : proc = null;

  void bindLogStream(
    String id,
    Process p,
    void Function(String, String, [Map<String, dynamic>?]) emit,
  ) {
    subs.add(
      p.stdout
          .transform(const SystemEncoding().decoder)
          .listen((d) => emit(id, 'log', {'message': d.trim()})),
    );
    subs.add(
      p.stderr
          .transform(const SystemEncoding().decoder)
          .listen((d) => emit(id, 'log', {'message': d.trim()})),
    );
  }

  void bindClamav(
    String id,
    Process p,
    void Function(String, String, [Map<String, dynamic>?]) emit,
  ) {
    subs.add(
      p.stdout.transform(const SystemEncoding().decoder).listen((chunk) {
        for (final raw in chunk.split('\n')) {
          final line = raw.trimRight();
          if (line.trim().isNotEmpty) emit(id, 'log', {'message': line});
        }
        final r = ClamScanOutputParser.parse(chunk);
        if (r.isEmpty) return;
        for (final t in r.threats) {
          emit(id, 'threat', {
            'filePath': t.filePath,
            'threatName': t.threatName,
          });
        }
        emit(id, 'progress', {
          if (r.totalScanned != null) 'totalScanned': r.totalScanned,
          'incrementalScanned': r.fileScannedIncrement,
        });
      }),
    );
    subs.add(
      p.stderr
          .transform(const SystemEncoding().decoder)
          .listen((d) => emit(id, 'log', {'message': d.trim()})),
    );
  }

  void bindRkhunter(
    String id,
    Process p,
    void Function(String, String, [Map<String, dynamic>?]) emit,
  ) {
    subs.add(
      p.stdout.transform(const SystemEncoding().decoder).listen((chunk) {
        for (final raw in chunk.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          emit(id, 'log', {'message': line});
          final finding = RkhunterOutputParser.parseWarningLine(line);
          if (finding != null) {
            emit(id, 'threat', {
              'filePath': finding.filePath,
              'threatName': finding.threatName,
              if (finding.details != null) 'details': finding.details,
            });
          }
        }
        emit(id, 'progress', {'incrementalScanned': 1});
      }),
    );
    subs.add(
      p.stderr
          .transform(const SystemEncoding().decoder)
          .listen((d) => emit(id, 'log', {'message': d.trim()})),
    );
  }

  void bindChkrootkit(
    String id,
    Process p,
    void Function(String, String, [Map<String, dynamic>?]) emit,
  ) {
    subs.add(
      p.stdout.transform(const SystemEncoding().decoder).listen((chunk) {
        for (final raw in chunk.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          emit(id, 'log', {'message': line});
          emit(id, 'threat', {'filePath': '(系统级检查)', 'threatName': line});
        }
        emit(id, 'progress', {'incrementalScanned': 1});
      }),
    );
    subs.add(
      p.stderr.transform(const SystemEncoding().decoder).listen((d) {
        final s = d.trim();
        if (s.isNotEmpty) emit(id, 'log', {'message': s});
      }),
    );
  }

  void dispose() {
    for (final s in subs) {
      unawaited(s.cancel());
    }
    subs.clear();
  }
}

class _PackageManager {
  final String executable;
  final List<String> Function(EnginePackages) installArgsFor;
  _PackageManager({required this.executable, required this.installArgsFor});

  factory _PackageManager.apt() => _PackageManager(
    executable: 'apt',
    installArgsFor: (p) => ['install', '-y', ...p.apt],
  );
  factory _PackageManager.pacman() => _PackageManager(
    executable: 'pacman',
    installArgsFor: (p) => ['-S', '--noconfirm', ...p.pacman],
  );
  factory _PackageManager.dnf() => _PackageManager(
    executable: 'dnf',
    installArgsFor: (p) => ['install', '-y', ...p.dnf],
  );
  factory _PackageManager.yum() => _PackageManager(
    executable: 'yum',
    installArgsFor: (p) => ['install', '-y', ...p.dnf],
  );
  factory _PackageManager.zypper() => _PackageManager(
    executable: 'zypper',
    installArgsFor: (p) => ['install', '-y', ...p.zypper],
  );
}
