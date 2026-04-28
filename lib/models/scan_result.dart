enum ScanAction { detected, removed, quarantined, skipped }

class ScanResult {
  final String filePath;
  final String threatName;
  final DateTime timestamp;
  final ScanAction action;
  final String engine; // 'clamav', 'rkhunter', 'chkrootkit'
  final String? details;

  const ScanResult({
    required this.filePath,
    required this.threatName,
    required this.timestamp,
    required this.action,
    required this.engine,
    this.details,
  });

  ScanResult copyWith({
    String? filePath,
    String? threatName,
    DateTime? timestamp,
    ScanAction? action,
    String? engine,
    String? details,
  }) {
    return ScanResult(
      filePath: filePath ?? this.filePath,
      threatName: threatName ?? this.threatName,
      timestamp: timestamp ?? this.timestamp,
      action: action ?? this.action,
      engine: engine ?? this.engine,
      details: details ?? this.details,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'threatName': threatName,
      'timestamp': timestamp.toIso8601String(),
      'action': action.toString(),
      'engine': engine,
      'details': details,
    };
  }

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      filePath: json['filePath'] as String,
      threatName: json['threatName'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      action: ScanAction.values.firstWhere(
        (e) => e.toString() == json['action'],
        orElse: () => ScanAction.detected,
      ),
      engine: json['engine'] as String? ?? 'clamav',
      details: json['details'] as String?,
    );
  }

  String get actionText => switch (action) {
    ScanAction.detected => '检测到',
    ScanAction.removed => '已删除',
    ScanAction.quarantined => '已隔离',
    ScanAction.skipped => '已跳过',
  };
}
