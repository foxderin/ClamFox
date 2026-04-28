/// Pure-function parser for `clamscan --verbose --infected` stdout.
///
/// Returns a [ScanChunkResult] describing the events found in one stdout chunk.
/// Stateless — caller accumulates totals.
class ClamScanOutputParser {
  /// Parse a single chunk of clamscan stdout.
  /// A "chunk" may contain multiple newline-separated lines.
  static ScanChunkResult parse(String chunk) {
    final threats = <DetectedThreat>[];
    int? totalScanned;
    int? totalInfected;
    int fileScannedIncrement = 0;

    for (final raw in chunk.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.contains('FOUND')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          final filePath = parts[0].trim();
          final threat =
              parts.sublist(1).join(':').replaceAll('FOUND', '').trim();
          if (filePath.isNotEmpty && threat.isNotEmpty) {
            threats.add(DetectedThreat(filePath: filePath, threatName: threat));
          }
        }
      } else if (line.contains('Scanned files:')) {
        final m = RegExp(r'Scanned files:\s*(\d+)').firstMatch(line);
        if (m != null) totalScanned = int.parse(m.group(1)!);
      } else if (line.contains('Infected files:')) {
        final m = RegExp(r'Infected files:\s*(\d+)').firstMatch(line);
        if (m != null) totalInfected = int.parse(m.group(1)!);
      } else if (line.endsWith('OK') || line.endsWith('Empty file')) {
        fileScannedIncrement++;
      }
    }

    return ScanChunkResult(
      threats: threats,
      totalScanned: totalScanned,
      totalInfected: totalInfected,
      fileScannedIncrement: fileScannedIncrement,
    );
  }
}

class DetectedThreat {
  final String filePath;
  final String threatName;
  const DetectedThreat({required this.filePath, required this.threatName});
}

class ScanChunkResult {
  /// New threats detected in this chunk (per FOUND line).
  final List<DetectedThreat> threats;

  /// Authoritative cumulative scanned-file count from a `Scanned files:` summary
  /// line. `null` if no such summary appeared in this chunk.
  final int? totalScanned;

  /// Authoritative cumulative infected count from `Infected files:` summary.
  final int? totalInfected;

  /// Number of per-file `... OK` lines observed in this chunk; caller adds
  /// to its running counter while no summary line has arrived.
  final int fileScannedIncrement;

  const ScanChunkResult({
    required this.threats,
    required this.totalScanned,
    required this.totalInfected,
    required this.fileScannedIncrement,
  });

  bool get isEmpty =>
      threats.isEmpty &&
      totalScanned == null &&
      totalInfected == null &&
      fileScannedIncrement == 0;
}
