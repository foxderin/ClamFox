// Print the ClamFox polkit policy XML to stdout.
//
// Usage:
//   dart run tool/dump_polkit_policy.dart
//
// Used by scripts/install_helper.sh so the policy XML stays in sync with
// lib/services/polkit_policy.dart instead of being duplicated in shell.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:clamfox/services/polkit_policy.dart';

void main() {
  stdout.writeln(buildClamfoxPolkitPolicy());
}
