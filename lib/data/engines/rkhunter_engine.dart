import 'dart:async';
import 'dart:io';

import '../../models/scan_result.dart';
import '../../services/polkit_service.dart';
import 'rkhunter_output_parser.dart';
import 'scan_engine.dart';

/// rkhunter — Rootkit Hunter. System-wide rootkit / backdoor scanner.
///
/// Output (with `--report-warnings-only`) is a stream of lines like:
///   Warning: The file properties have changed: /usr/bin/foo
///   Warning: Hidden directory found: /etc/.something
/// We treat parsed warning findings as [ScanThreatFound] and keep raw output
/// as [ScanLog].
class RkhunterEngine implements ScanEngine {
  final PolkitService _polkit;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  RkhunterEngine({PolkitService? polkit}) : _polkit = polkit ?? PolkitService();

  @override
  String get id => 'rkhunter';
  @override
  String get displayName => 'rkhunter';
  @override
  String get description => 'Rootkit / 后门 / 系统完整性检查（需要 root）';
  @override
  bool get supportsPathScan => false;

  @override
  Future<EngineAvailability> checkAvailability() async {
    // Try the unprivileged version probe first. Works on distros where the
    // binary is world-executable (some Debian/Ubuntu builds).
    try {
      final r = await Process.run('rkhunter', ['--version']);
      if (r.exitCode == 0) {
        final lines = r.stdout
            .toString()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        return EngineAvailability(
          installed: true,
          version: lines.isNotEmpty ? lines.first : null,
        );
      }
    } on ProcessException {
      // Some distros (e.g. Arch) ship rkhunter as 0700 root:root, so an
      // unprivileged exec fails with EACCES. Fall through to filesystem
      // detection rather than declaring it missing.
    }

    for (final p in const [
      '/usr/bin/rkhunter',
      '/usr/sbin/rkhunter',
      '/usr/local/bin/rkhunter',
      '/usr/local/sbin/rkhunter',
    ]) {
      if (File(p).existsSync()) {
        return const EngineAvailability(installed: true);
      }
    }

    return const EngineAvailability(installed: false, hint: '请安装 rkhunter');
  }

  @override
  Stream<ScanEvent> scan({String? path}) async* {
    final controller = StreamController<ScanEvent>();
    final available = await PolkitService.isPolkitAvailable();
    final args = [
      '--check',
      '--skip-keypress',
      '--report-warnings-only',
      '--no-mail-on-warning',
    ];

    try {
      _process = available
          ? await _polkit.startPrivilegedProcess('rkhunter', args)
          : await Process.start('sudo', ['rkhunter', ...args]);

      controller.add(const ScanStarted());

      _stdoutSub = _process!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
            for (final raw in chunk.split('\n')) {
              final line = raw.trim();
              if (line.isEmpty) continue;
              controller.add(ScanLog(line));
              final finding = RkhunterOutputParser.parseWarningLine(line);
              if (finding != null) {
                controller.add(
                  ScanThreatFound(
                    ScanResult(
                      filePath: finding.filePath,
                      threatName: finding.threatName,
                      timestamp: DateTime.now(),
                      action: ScanAction.detected,
                      engine: id,
                      details: finding.details,
                    ),
                  ),
                );
              }
            }
            // rkhunter doesn't print per-file counts; emit a heartbeat tick so
            // the UI knows we are alive.
            controller.add(const ScanFileProgress(incrementalScanned: 1));
          });

      _stderrSub = _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((d) {
            final s = d.trim();
            if (s.isNotEmpty) controller.add(ScanLog(s));
          });

      _process!.exitCode.then((code) {
        // rkhunter exit codes: 0 = clean, 1 = warnings/errors, 2 = no
        // signature update; treat anything > 1 as a hard failure only.
        if (code > 1) {
          controller.add(ScanFailed(message: 'rkhunter 异常退出（退出码 $code）'));
        }
        controller.add(ScanFinished(exitCode: code));
        controller.close();
      });

      yield* controller.stream;
    } on ProcessException catch (e) {
      yield ScanFailed(message: 'rkhunter 启动失败: ${e.message}');
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
