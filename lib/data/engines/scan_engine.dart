import 'dart:async';
import '../../models/scan_result.dart';

/// One concrete antivirus / rootkit-detection engine.
///
/// Each engine wraps a CLI tool (clamscan, rkhunter, chkrootkit, ...).
/// Implementations stream [ScanEvent]s while running so the UI can show
/// live progress and detections.
abstract class ScanEngine {
  /// Stable identifier used in [ScanResult.engine] and persistence.
  /// Examples: 'clamav', 'rkhunter', 'chkrootkit'.
  String get id;

  /// Human-readable name shown in UI.
  String get displayName;

  /// One-line description shown next to the engine selector.
  String get description;

  /// True if this engine scans arbitrary user paths (ClamAV).
  /// False for system-wide rootkit scanners (rkhunter, chkrootkit) —
  /// the UI hides path pickers for those.
  bool get supportsPathScan;

  /// Detect whether the underlying CLI is available on the host.
  Future<EngineAvailability> checkAvailability();

  /// Run a scan. For [supportsPathScan]=false engines, [path] is ignored.
  /// The returned [Stream] emits events until the process exits.
  /// Cancel by calling [cancel].
  Stream<ScanEvent> scan({String? path});

  /// Best-effort cancel of the currently running scan, if any.
  Future<void> cancel();
}

class EngineAvailability {
  final bool installed;
  final String? version;
  final String? hint; // why missing / install command suggestion
  const EngineAvailability({required this.installed, this.version, this.hint});

  static const missing = EngineAvailability(installed: false);
}

/// Streamed events emitted by an engine while scanning.
sealed class ScanEvent {
  const ScanEvent();
}

class ScanStarted extends ScanEvent {
  final String? path;
  const ScanStarted({this.path});
}

class ScanFileProgress extends ScanEvent {
  /// Cumulative file count from the engine's authoritative summary, or null
  /// when the count comes from per-file lines.
  final int? totalScanned;

  /// Number of newly scanned files since the last event (per-file lines).
  final int incrementalScanned;
  const ScanFileProgress({this.totalScanned, this.incrementalScanned = 0});
}

class ScanThreatFound extends ScanEvent {
  final ScanResult result;
  const ScanThreatFound(this.result);
}

class ScanLog extends ScanEvent {
  final String message;
  const ScanLog(this.message);
}

class ScanFailed extends ScanEvent {
  final String message;
  const ScanFailed({required this.message});
}

class ScanFinished extends ScanEvent {
  final int? exitCode;
  const ScanFinished({this.exitCode});
}
