class ScanSettings {
  final bool scanArchives;
  final bool scanEmails;
  final bool removeInfected;
  final bool quarantine;
  final bool recursiveScan;
  final int maxFileSize; // in MB, 0 means no limit
  final List<String> excludedExtensions;
  final List<String> excludedPaths;
  final bool followSymlinks;
  final bool detectPua; // Potentially Unwanted Applications

  const ScanSettings({
    this.scanArchives = true,
    this.scanEmails = true,
    this.removeInfected = false,
    this.quarantine = false,
    this.recursiveScan = true,
    this.maxFileSize = 0,
    this.excludedExtensions = const [],
    this.excludedPaths = const [],
    this.followSymlinks = false,
    this.detectPua = false,
  });

  ScanSettings copyWith({
    bool? scanArchives,
    bool? scanEmails,
    bool? removeInfected,
    bool? quarantine,
    bool? recursiveScan,
    int? maxFileSize,
    List<String>? excludedExtensions,
    List<String>? excludedPaths,
    bool? followSymlinks,
    bool? detectPua,
  }) {
    return ScanSettings(
      scanArchives: scanArchives ?? this.scanArchives,
      scanEmails: scanEmails ?? this.scanEmails,
      removeInfected: removeInfected ?? this.removeInfected,
      quarantine: quarantine ?? this.quarantine,
      recursiveScan: recursiveScan ?? this.recursiveScan,
      maxFileSize: maxFileSize ?? this.maxFileSize,
      excludedExtensions: excludedExtensions ?? this.excludedExtensions,
      excludedPaths: excludedPaths ?? this.excludedPaths,
      followSymlinks: followSymlinks ?? this.followSymlinks,
      detectPua: detectPua ?? this.detectPua,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scanArchives': scanArchives,
      'scanEmails': scanEmails,
      'removeInfected': removeInfected,
      'quarantine': quarantine,
      'recursiveScan': recursiveScan,
      'maxFileSize': maxFileSize,
      'excludedExtensions': excludedExtensions,
      'excludedPaths': excludedPaths,
      'followSymlinks': followSymlinks,
      'detectPua': detectPua,
    };
  }

  factory ScanSettings.fromJson(Map<String, dynamic> json) {
    return ScanSettings(
      scanArchives: json['scanArchives'] ?? true,
      scanEmails: json['scanEmails'] ?? true,
      removeInfected: json['removeInfected'] ?? false,
      quarantine: json['quarantine'] ?? false,
      recursiveScan: json['recursiveScan'] ?? true,
      maxFileSize: json['maxFileSize'] ?? 0,
      excludedExtensions: List<String>.from(json['excludedExtensions'] ?? []),
      excludedPaths: List<String>.from(json['excludedPaths'] ?? []),
      followSymlinks: json['followSymlinks'] ?? false,
      detectPua: json['detectPua'] ?? false,
    );
  }
}
