import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_result.dart';
import '../models/scan_session.dart';
import 'engines/chkrootkit_output_parser.dart';
import 'engines/rkhunter_output_parser.dart';

/// Persists scan history across app restarts.
///
/// Backed by SharedPreferences key `scan_history`. Sessions are stored as a
/// JSON array, oldest first. Capped at [maxSessions] with FIFO eviction.
class ScanHistoryRepository {
  static const _key = 'scan_history';
  static const maxSessions = 50;

  Future<List<ScanSession>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return <ScanSession>[];
      final list = jsonDecode(raw) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(ScanSession.fromJson)
          .map(_normalizeLegacySession)
          .toList();
    } catch (e) {
      debugPrint('扫描历史加载失败: $e');
      return <ScanSession>[];
    }
  }

  Future<void> append(ScanSession session) async {
    try {
      final loaded = await loadAll();
      // loadAll may return `const []` on the empty-prefs path in older
      // Dart releases — copy to a fresh growable list before mutating.
      final all = List<ScanSession>.of(loaded)..add(session);
      while (all.length > maxSessions) {
        all.removeAt(0);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(all.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('扫描历史保存失败: $e');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('扫描历史清空失败: $e');
    }
  }

  ScanSession _normalizeLegacySession(ScanSession session) {
    if ((session.engine != 'rkhunter' && session.engine != 'chkrootkit') ||
        session.results.isEmpty) {
      return session;
    }

    var changed = false;
    final results = <ScanResult>[];
    for (final result in session.results) {
      final repaired = switch (session.engine) {
        'rkhunter' => _repairLegacyRkhunterResult(result),
        'chkrootkit' => _repairLegacyChkrootkitResult(result),
        _ => result,
      };
      if (repaired == null) {
        changed = true;
        continue;
      }
      if (!identical(repaired, result)) changed = true;
      results.add(repaired);
    }

    if (!changed) return session;
    return ScanSession(
      id: session.id,
      startedAt: session.startedAt,
      finishedAt: session.finishedAt,
      engine: session.engine,
      target: session.target,
      filesScanned: session.filesScanned,
      threatsFound: results.length,
      results: results,
      logs: session.logs,
      cancelled: session.cancelled,
    );
  }

  ScanResult? _repairLegacyRkhunterResult(ScanResult result) {
    if (result.engine != 'rkhunter') return result;
    final commandScript =
        result.threatName.startsWith("The command '") &&
        result.threatName.contains(' has been replaced by a script');
    if (!commandScript &&
        result.details != null &&
        result.details!.isNotEmpty) {
      return result;
    }

    final shouldRepair =
        commandScript ||
        result.filePath == '(系统级检查)' ||
        !result.filePath.startsWith('/') ||
        result.threatName.contains(': /');
    if (!shouldRepair) return result;

    final finding = RkhunterOutputParser.parseLegacyFinding(
      threatName: result.threatName,
      filePath: result.filePath,
    );
    if (finding == null) return null;

    final details = finding.details ?? result.details;
    if (finding.threatName == result.threatName &&
        finding.filePath == result.filePath &&
        details == result.details) {
      return result;
    }

    return result.copyWith(
      threatName: finding.threatName,
      filePath: finding.filePath,
      details: details,
    );
  }

  ScanResult? _repairLegacyChkrootkitResult(ScanResult result) {
    if (result.engine != 'chkrootkit') return result;
    if (result.details != null && result.details!.isNotEmpty) return result;

    final finding = ChkrootkitOutputParser.parseLegacyFinding(
      threatName: result.threatName,
      filePath: result.filePath,
    );
    if (finding == null) return null;

    if (finding.threatName == result.threatName &&
        finding.filePath == result.filePath &&
        finding.details == result.details) {
      return result;
    }

    return result.copyWith(
      threatName: finding.threatName,
      filePath: finding.filePath,
      details: finding.details,
    );
  }
}
