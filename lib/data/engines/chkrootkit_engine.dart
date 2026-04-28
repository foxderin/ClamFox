import 'dart:async';
import 'dart:io';

import '../../models/scan_result.dart';
import '../../services/polkit_service.dart';
import 'scan_engine.dart';

/// chkrootkit — local rootkit / suspicious-binary scanner.
///
/// We invoke `chkrootkit -q` (quiet); only positive findings are printed,
/// formatted as `Checking `name'... INFECTED` or similar. Any non-empty
/// stdout line in quiet mode is treated as a finding.
class ChkrootkitEngine implements ScanEngine {
  final PolkitService _polkit;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  ChkrootkitEngine({PolkitService? polkit})
    : _polkit = polkit ?? PolkitService();

  @override
  String get id => 'chkrootkit';
  @override
  String get displayName => 'chkrootkit';
  @override
  String get description => 'Rootkit 二次确认扫描（需要 root）';
  @override
  bool get supportsPathScan => false;

  @override
  Future<EngineAvailability> checkAvailability() async {
    // Unprivileged version probe first (works where the binary is world-
    // executable; gracefully degrade on distros that ship it as root-only).
    try {
      final r = await Process.run('chkrootkit', ['-V']);
      final out = (r.stdout.toString() + r.stderr.toString()).trim();
      if (out.toLowerCase().contains('chkrootkit')) {
        return EngineAvailability(
          installed: true,
          version: out.split('\n').first.trim(),
        );
      }
    } on ProcessException {
      // EACCES on root-only installs — fall through to filesystem detection.
    }

    for (final p in const [
      '/usr/bin/chkrootkit',
      '/usr/sbin/chkrootkit',
      '/usr/local/bin/chkrootkit',
      '/usr/local/sbin/chkrootkit',
    ]) {
      if (File(p).existsSync()) {
        return const EngineAvailability(installed: true);
      }
    }

    return const EngineAvailability(installed: false, hint: '请安装 chkrootkit');
  }

  @override
  Stream<ScanEvent> scan({String? path}) async* {
    final controller = StreamController<ScanEvent>();
    final available = await PolkitService.isPolkitAvailable();
    const args = ['-q'];

    try {
      _process = available
          ? await _polkit.startPrivilegedProcess('chkrootkit', args)
          : await Process.start('sudo', ['chkrootkit', ...args]);

      controller.add(const ScanStarted());

      _stdoutSub = _process!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
            for (final raw in chunk.split('\n')) {
              final line = raw.trim();
              if (line.isEmpty) continue;
              controller.add(ScanLog(line));
              // Quiet mode only emits suspicious / infected lines.
              // Examples:
              //   "INFECTED (PORTS:  465)"
              //   "Possible Linux/Ebury - Operation Windigo installed"
              controller.add(
                ScanThreatFound(
                  ScanResult(
                    filePath: '(系统级检查)',
                    threatName: line,
                    timestamp: DateTime.now(),
                    action: ScanAction.detected,
                    engine: id,
                  ),
                ),
              );
            }
            controller.add(const ScanFileProgress(incrementalScanned: 1));
          });

      _stderrSub = _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((d) {
            final s = d.trim();
            if (s.isNotEmpty) controller.add(ScanLog(s));
          });

      _process!.exitCode.then((code) {
        if (code != 0) {
          controller.add(ScanFailed(message: 'chkrootkit 异常退出（退出码 $code）'));
        }
        controller.add(ScanFinished(exitCode: code));
        controller.close();
      });

      yield* controller.stream;
    } on ProcessException catch (e) {
      yield ScanFailed(message: 'chkrootkit 启动失败: ${e.message}');
      yield const ScanFinished();
    } finally {
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
      _stdoutSub = null;
      _stderrSub = null;
      _process = null;
    }
  }

  @override
  Future<void> cancel() async {
    final p = _process;
    if (p == null) return;
    p.kill(ProcessSignal.sigterm);
    Timer(const Duration(seconds: 3), () {
      _process?.kill(ProcessSignal.sigkill);
    });
  }
}
