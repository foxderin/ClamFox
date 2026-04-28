import 'scan_result.dart';

/// One full scan run: from start to either completion or cancellation.
class ScanSession {
  final String id; // unique, derived from startedAt timestamp
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String engine; // 'clamav' | 'rkhunter' | 'chkrootkit'
  final String target; // '/home', '/', or '系统级扫描' for engines without paths
  final int filesScanned;
  final int threatsFound;
  final List<ScanResult> results;
  final List<String> logs;
  final bool cancelled;

  const ScanSession({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.engine,
    required this.target,
    required this.filesScanned,
    required this.threatsFound,
    required this.results,
    this.logs = const [],
    required this.cancelled,
  });

  Duration? get duration => finishedAt?.difference(startedAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'engine': engine,
    'target': target,
    'filesScanned': filesScanned,
    'threatsFound': threatsFound,
    'cancelled': cancelled,
    'results': results.map((r) => r.toJson()).toList(),
    'logs': logs,
  };

  factory ScanSession.fromJson(Map<String, dynamic> json) {
    return ScanSession(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      engine: json['engine'] as String? ?? 'clamav',
      target: json['target'] as String? ?? '',
      filesScanned: (json['filesScanned'] as num?)?.toInt() ?? 0,
      threatsFound: (json['threatsFound'] as num?)?.toInt() ?? 0,
      cancelled: json['cancelled'] as bool? ?? false,
      results: ((json['results'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ScanResult.fromJson)
          .toList(),
      logs: ((json['logs'] as List?) ?? const [])
          .map((line) => line.toString())
          .toList(),
    );
  }
}
