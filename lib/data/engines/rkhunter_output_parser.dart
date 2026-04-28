class RkhunterFinding {
  final String threatName;
  final String filePath;
  final String? details;

  const RkhunterFinding({
    required this.threatName,
    required this.filePath,
    this.details,
  });
}

class RkhunterOutputParser {
  static final RegExp _warningLine = RegExp(
    r'^(?:\[[^\]]+\]\s*)?Warning:\s*(.+)$',
  );
  static final RegExp _statusWarning = RegExp(r'\[\s*Warning\s*\]$');
  static final RegExp _commandScript = RegExp(
    r"^The command '([^']+)' has been replaced by a script:\s*(.+)$",
  );
  static final RegExp _hiddenEntry = RegExp(
    r'^(Hidden (?:file|directory) found):\s*(.+)$',
  );
  static final RegExp _suspiciousFileTypes = RegExp(
    r'^(Suspicious file types found in)\s+([^:]+)(?::\s*(.*))?$',
  );
  static final RegExp _absolutePath = RegExp(r'/[^\s:]+');

  static RkhunterFinding? parseWarningLine(String line) {
    final match = _warningLine.firstMatch(line.trim());
    if (match == null) return null;

    final body = match.group(1)!.trim();
    if (body.isEmpty || _isNonFindingWarning(body)) return null;

    final commandMatch = _commandScript.firstMatch(body);
    if (commandMatch != null) {
      final command = commandMatch.group(1)!.trim();
      final parsed = _parsePathAndDetails(
        commandMatch.group(2)!,
        fallbackPath: command,
      );
      return RkhunterFinding(
        threatName: "The command '$command' has been replaced by a script",
        filePath: parsed.filePath,
        details: parsed.details,
      );
    }

    final hiddenMatch = _hiddenEntry.firstMatch(body);
    if (hiddenMatch != null) {
      final parsed = _parsePathAndDetails(hiddenMatch.group(2)!);
      return RkhunterFinding(
        threatName: hiddenMatch.group(1)!.trim(),
        filePath: parsed.filePath,
        details: parsed.details,
      );
    }

    final suspiciousMatch = _suspiciousFileTypes.firstMatch(body);
    if (suspiciousMatch != null) {
      final details = suspiciousMatch.group(3)?.trim();
      return RkhunterFinding(
        threatName: suspiciousMatch.group(1)!.trim(),
        filePath: suspiciousMatch.group(2)!.trim(),
        details: details == null || details.isEmpty ? null : details,
      );
    }

    return _parseGenericFinding(body);
  }

  static RkhunterFinding? parseLegacyFinding({
    required String threatName,
    required String filePath,
  }) {
    final line = filePath == '(系统级检查)'
        ? 'Warning: $threatName'
        : 'Warning: $threatName: $filePath';
    return parseWarningLine(line);
  }

  static bool _isNonFindingWarning(String body) {
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.startsWith('WARNING!') ||
        (normalized.startsWith('Checking ') &&
            _statusWarning.hasMatch(normalized)) ||
        (normalized.contains('users responsibility') &&
            normalized.contains("'--propupd'"));
  }

  static RkhunterFinding _parseGenericFinding(String body) {
    final pathMatch = _absolutePath.firstMatch(body);
    if (pathMatch == null) {
      return RkhunterFinding(threatName: body, filePath: '(系统级检查)');
    }

    final path = pathMatch.group(0)!.trim();
    final beforePath = body.substring(0, pathMatch.start).trimRight();
    final afterPath = body.substring(pathMatch.end).trim();
    final details = afterPath.startsWith(':')
        ? afterPath.substring(1).trim()
        : null;

    final pathIntroducedByColon = beforePath.endsWith(':');
    final threat = pathIntroducedByColon
        ? beforePath.substring(0, beforePath.length - 1).trim()
        : body;

    return RkhunterFinding(
      threatName: threat.isEmpty ? body : threat,
      filePath: path,
      details: details == null || details.isEmpty ? null : details,
    );
  }

  static ({String filePath, String? details}) _parsePathAndDetails(
    String value, {
    String fallbackPath = '(系统级检查)',
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return (filePath: fallbackPath, details: null);

    final separator = trimmed.indexOf(': ');
    if (separator > 0) {
      final path = trimmed.substring(0, separator).trim();
      final details = trimmed.substring(separator + 2).trim();
      if (_looksLikePath(path)) {
        return (filePath: path, details: details.isEmpty ? null : details);
      }
    }

    if (_looksLikePath(trimmed)) {
      return (filePath: trimmed, details: null);
    }

    return (filePath: fallbackPath, details: trimmed);
  }

  static bool _looksLikePath(String value) => value.startsWith('/');
}
