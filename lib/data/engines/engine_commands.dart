// Pure-Dart shared constants and command builders.
//
// This file MUST NOT import package:flutter or anything that pulls Flutter
// in transitively — `bin/clamfox_helper.dart` (the standalone root daemon)
// imports it and would fail to compile otherwise.

import 'package:clamfox/models/scan_settings.dart';

class EngineCommands {
  static const List<String> allowedEngines = [
    'clamav',
    'rkhunter',
    'chkrootkit',
  ];

  static bool isValidEngine(String? id) =>
      id != null && allowedEngines.contains(id);

  /// Unprivileged version probe arguments. Returns the binary name + args.
  static const Map<String, List<String>> versionArgs = {
    'clamav': ['clamscan', '--version'],
    'rkhunter': ['rkhunter', '--version'],
    'chkrootkit': ['chkrootkit', '-V'],
  };

  /// Common install paths for filesystem-existence fallback (some distros
  /// ship rkhunter/chkrootkit as 0700 root:root, so a non-root probe of the
  /// binary fails with EACCES even when installed).
  static const Map<String, List<String>> binaryPaths = {
    'clamav': ['/usr/bin/clamscan', '/usr/local/bin/clamscan'],
    'rkhunter': [
      '/usr/bin/rkhunter',
      '/usr/sbin/rkhunter',
      '/usr/local/bin/rkhunter',
      '/usr/local/sbin/rkhunter',
    ],
    'chkrootkit': [
      '/usr/bin/chkrootkit',
      '/usr/sbin/chkrootkit',
      '/usr/local/bin/chkrootkit',
      '/usr/local/sbin/chkrootkit',
    ],
  };

  /// Scan args for engines that don't take a user path.
  static const List<String> rkhunterScanArgs = [
    '--check',
    '--skip-keypress',
    '--report-warnings-only',
    '--no-mail-on-warning',
  ];

  static const List<String> chkrootkitScanArgs = ['-q'];

  /// Database / signature update commands. chkrootkit has no remote update.
  static const Map<String, List<String>> updateCommand = {
    'clamav': ['freshclam'],
    'rkhunter': ['rkhunter', '--update', '--propupd'],
  };

  /// Build clamscan args from validated settings + an absolute scan path.
  /// Used by both the main process (legacy direct-spawn path) and the
  /// privileged helper.
  static List<String> buildClamscanArgs({
    required ScanSettings settings,
    required String path,
    required String quarantineDir,
  }) {
    return <String>[
      if (settings.recursiveScan) '--recursive',
      '--bell',
      '--verbose',
      if (settings.removeInfected) '--remove',
      if (settings.quarantine) '--move=$quarantineDir',
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
  }
}

/// Per-distro package list for installing an engine.
class EnginePackages {
  final List<String> apt;
  final List<String> pacman;
  final List<String> dnf;
  final List<String> zypper;

  const EnginePackages({
    required this.apt,
    required this.pacman,
    required this.dnf,
    required this.zypper,
  });

  bool get isEmpty =>
      apt.isEmpty && pacman.isEmpty && dnf.isEmpty && zypper.isEmpty;

  static const Map<String, EnginePackages> byEngine = {
    'clamav': EnginePackages(
      apt: ['clamav', 'clamav-daemon', 'clamav-freshclam'],
      pacman: ['clamav'],
      dnf: ['clamav', 'clamav-update'],
      zypper: ['clamav'],
    ),
    'rkhunter': EnginePackages(
      apt: ['rkhunter'],
      pacman: ['rkhunter'],
      dnf: ['rkhunter'],
      zypper: ['rkhunter'],
    ),
    'chkrootkit': EnginePackages(
      apt: ['chkrootkit'],
      pacman: ['chkrootkit'],
      dnf: ['chkrootkit'],
      zypper: ['chkrootkit'],
    ),
  };
}

/// Allowlist of supported package managers.
const List<String> kAllowedPackageManagers = [
  'apt',
  'pacman',
  'dnf',
  'yum',
  'zypper',
];
