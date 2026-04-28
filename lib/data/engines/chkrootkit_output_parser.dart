class ChkrootkitFinding {
  final String threatName;
  final String filePath;
  final String? details;

  const ChkrootkitFinding({
    required this.threatName,
    required this.filePath,
    this.details,
  });
}

class ChkrootkitOutputParser {
  static final RegExp _checkingInfected = RegExp(
    r"^Checking [`']([^`']+)[`']\.\.\. INFECTED$",
  );
  static final RegExp _suspectDirectory = RegExp(
    r'^Suspect directory\s+(.+?)\s+FOUND!(?:\s*(.*))?$',
  );
  static final RegExp _warning = RegExp(
    r'^(?:[A-Za-z0-9_-]+:\s*)?Warning:\s*(.+)$',
  );
  static final RegExp _absolutePath = RegExp(r'/[^\s:]+');
  static final RegExp _barePathList = RegExp(r'^/\S+(?:\s+/\S+)+$');

  static ChkrootkitFinding? parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || _isNonFinding(trimmed)) return null;

    final checking = _checkingInfected.firstMatch(trimmed);
    if (checking != null) {
      final checkName = checking.group(1)!.trim();
      return ChkrootkitFinding(
        threatName: '$checkName 检测项报告 INFECTED',
        filePath: '(系统级检查)',
        details: trimmed,
      );
    }

    final suspectDirectory = _suspectDirectory.firstMatch(trimmed);
    if (suspectDirectory != null) {
      final path = _normalizePath(suspectDirectory.group(1)!.trim());
      final details = suspectDirectory.group(2)?.trim();
      return ChkrootkitFinding(
        threatName: 'Suspect directory found',
        filePath: path,
        details: details == null || details.isEmpty ? null : details,
      );
    }

    final warning = _warning.firstMatch(trimmed);
    if (warning != null) {
      return _parseFindingText(warning.group(1)!.trim(), original: trimmed);
    }

    if (_isFindingText(trimmed)) {
      return _parseFindingText(trimmed);
    }

    final singlePath = _singleAbsolutePath(trimmed);
    if (singlePath != null) {
      return ChkrootkitFinding(
        threatName: 'Suspicious file reported by chkrootkit',
        filePath: singlePath,
      );
    }

    return null;
  }

  static ChkrootkitFinding? parseLegacyFinding({
    required String threatName,
    required String filePath,
  }) {
    final finding = parseLine(threatName);
    if (finding != null) return finding;
    if (filePath != '(系统级检查)') return parseLine(filePath);
    return null;
  }

  static bool _isNonFinding(String line) {
    final lower = line.toLowerCase();
    return lower == 'not tested' ||
        lower.startsWith('not tested:') ||
        lower.startsWith("can't exec ") ||
        lower.startsWith('chkrootkit: can\'t exec') ||
        lower.startsWith('chkrootkit: can\'t exec/find') ||
        lower.startsWith('searching for ') ||
        lower == 'nothing found' ||
        lower == 'not infected' ||
        lower == 'no suspect files' ||
        _barePathList.hasMatch(line);
  }

  static bool _isFindingText(String line) {
    final lower = line.toLowerCase();
    return lower.contains('infected') ||
        lower.startsWith('possible ') ||
        lower.contains(': possible ') ||
        lower.startsWith('vulnerable') ||
        lower.contains(' packet sniffer');
  }

  static ChkrootkitFinding _parseFindingText(String text, {String? original}) {
    final pathMatch = _absolutePath.firstMatch(text);
    final details = original != null && original != text ? original : null;
    if (pathMatch == null) {
      return ChkrootkitFinding(
        threatName: text,
        filePath: '(系统级检查)',
        details: details,
      );
    }

    final path = pathMatch.group(0)!.trim();
    var threat = text.replaceFirst(path, '').replaceAll(RegExp(r'\s+'), ' ');
    threat = threat.replaceAll(RegExp(r'^\s*[:,-]\s*'), '').trim();
    threat = threat.replaceAll(RegExp(r'\s*[:,-]\s*$'), '').trim();

    return ChkrootkitFinding(
      threatName: threat.isEmpty ? text : threat,
      filePath: path,
      details: details,
    );
  }

  static String? _singleAbsolutePath(String line) {
    if (!line.startsWith('/') || line.contains(RegExp(r'\s'))) return null;
    return line;
  }

  static String _normalizePath(String path) {
    if (path.startsWith('/')) return path;
    return '/$path';
  }
}
