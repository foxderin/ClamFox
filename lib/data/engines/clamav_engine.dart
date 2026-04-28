import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/scan_result.dart';
import '../../models/scan_settings.dart';
import '../clamav/clamscan_output_parser.dart';
import 'scan_engine.dart';

class ClamAvEngine implements ScanEngine {
  final ScanSettings Function() _settingsProvider;
  final String Function() _quarantineDirProvider;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  ClamAvEngine({
    required ScanSettings Function() settingsProvider,
    required String Function() quarantineDirProvider,
  }) : _settingsProvider = settingsProvider,
       _quarantineDirProvider = quarantineDirProvider;

  @override
  String get id => 'clamav';

  @override
  String get displayName => 'ClamAV';

  @override
  String get description => '通用文件 / 目录病毒扫描';

  @override
  bool get supportsPathScan => true;

  @override
  Future<EngineAvailability> checkAvailability() async {
    try {
      final r = await Process.run('clamscan', ['--version']);
      if (r.exitCode != 0) {
        return const EngineAvailability(installed: false);
      }
      return EngineAvailability(
        installed: true,
        version: r.stdout.toString().trim(),
      );
    } on ProcessException {
      return const EngineAvailability(installed: false, hint: '请安装 clamav');
    }
  }

  @override
  Stream<ScanEvent> scan({String? path}) async* {
    if (path == null || path.isEmpty) {
      yield const ScanFailed(message: 'ClamAV 需要指定扫描路径');
      return;
    }
    final settings = _settingsProvider();
    final quarantine = _quarantineDirProvider();

    final args = <String>[
      if (settings.recursiveScan) '--recursive',
      '--bell',
      '--verbose',
      if (settings.removeInfected) '--remove',
      if (settings.quarantine) '--move=$quarantine',
      if (settings.scanArchives) '--scan-archive',
      if (settings.scanEmails) '--scan-mail',
      if (settings.detectPua) '--detect-pua',
      if (settings.followSymlinks) '--follow-dir-symlinks=2',
      if (settings.maxFileSize > 0) '--max-filesize=${settings.maxFileSize}M',
      for (final ext in settings.excludedExtensions)
        '--exclude=\\.${RegExp.escape(ext)}\$',
      for (final excl in settings.excludedPaths) '--exclude-dir=$excl',
      path,
    ];

    final controller = StreamController<ScanEvent>();
    try {
      _process = await Process.start('clamscan', args);
      controller.add(ScanStarted(path: path));

      _stdoutSub = _process!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
            for (final line in const LineSplitter().convert(chunk)) {
              if (line.trim().isNotEmpty) controller.add(ScanLog(line));
            }
            final r = ClamScanOutputParser.parse(chunk);
            if (r.isEmpty) return;
            for (final t in r.threats) {
              controller.add(
                ScanThreatFound(
                  ScanResult(
                    filePath: t.filePath,
                    threatName: t.threatName,
                    timestamp: DateTime.now(),
                    action: ScanAction.detected,
                    engine: id,
                  ),
                ),
              );
            }
            controller.add(
              ScanFileProgress(
                totalScanned: r.totalScanned,
                incrementalScanned: r.fileScannedIncrement,
              ),
            );
          });
      _stderrSub = _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((d) {
            if (d.trim().isNotEmpty) controller.add(ScanLog(d.trim()));
          });

      _process!.exitCode.then((code) {
        if (code > 1) {
          controller.add(ScanFailed(message: 'ClamAV 扫描错误（退出码 $code）'));
        }
        controller.add(ScanFinished(exitCode: code));
        controller.close();
      });

      yield* controller.stream;
    } on ProcessException catch (e) {
      yield ScanFailed(message: 'ClamAV 启动失败: ${e.message}');
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
