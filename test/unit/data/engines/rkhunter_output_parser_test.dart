import 'package:clamfox/data/engines/rkhunter_output_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RkhunterOutputParser.parseWarningLine', () {
    test('ignores status warning lines', () {
      final finding = RkhunterOutputParser.parseWarningLine(
        'Warning: Checking for prerequisites               [ Warning ]',
      );
      expect(finding, isNull);
    });

    test('ignores propupd disclaimer lines', () {
      final finding = RkhunterOutputParser.parseWarningLine(
        "Warning: WARNING! It is the users responsibility to ensure that when the '--propupd' option",
      );
      expect(finding, isNull);
    });

    test('parses unknown command script warnings with details', () {
      final finding = RkhunterOutputParser.parseWarningLine(
        "Warning: The command '/usr/bin/custom-tool' has been replaced by a script: /usr/bin/custom-tool: POSIX shell script, ASCII text executable",
      );

      expect(finding, isNotNull);
      expect(
        finding!.threatName,
        "The command '/usr/bin/custom-tool' has been replaced by a script",
      );
      expect(finding.filePath, '/usr/bin/custom-tool');
      expect(finding.details, 'POSIX shell script, ASCII text executable');
    });

    test('ignores known distro command script wrappers', () {
      for (final line in const [
        "Warning: The command '/usr/bin/egrep' has been replaced by a script: /usr/bin/egrep: POSIX shell script, ASCII text executable",
        "Warning: The command '/usr/bin/fgrep' has been replaced by a script: /usr/bin/fgrep: POSIX shell script, ASCII text executable",
        "Warning: The command '/usr/bin/ldd' has been replaced by a script: /usr/bin/ldd: Bourne-Again shell script, ASCII text executable",
      ]) {
        expect(RkhunterOutputParser.parseWarningLine(line), isNull);
      }
    });

    test('parses hidden files with file type details', () {
      final finding = RkhunterOutputParser.parseWarningLine(
        'Warning: Hidden file found: /etc/.updated: ASCII text',
      );

      expect(finding, isNotNull);
      expect(finding!.threatName, 'Hidden file found');
      expect(finding.filePath, '/etc/.updated');
      expect(finding.details, 'ASCII text');
    });

    test('parses suspicious file type directories', () {
      final finding = RkhunterOutputParser.parseWarningLine(
        'Warning: Suspicious file types found in /dev',
      );

      expect(finding, isNotNull);
      expect(finding!.threatName, 'Suspicious file types found in');
      expect(finding.filePath, '/dev');
      expect(finding.details, isNull);
    });

    test('keeps system-level warnings without a file path', () {
      final finding = RkhunterOutputParser.parseWarningLine(
        "Warning: The SSH configuration option 'PermitRootLogin' has not been set.",
      );

      expect(finding, isNotNull);
      expect(
        finding!.threatName,
        "The SSH configuration option 'PermitRootLogin' has not been set.",
      );
      expect(finding.filePath, '(系统级检查)');
      expect(finding.details, isNull);
    });

    test('repairs legacy copied command warnings', () {
      final finding = RkhunterOutputParser.parseLegacyFinding(
        threatName:
            "The command '/usr/bin/custom-tool' has been replaced by a script: /usr/bin/custom-tool",
        filePath: 'Bourne-Again shell script, ASCII text executable',
      );

      expect(finding, isNotNull);
      expect(
        finding!.threatName,
        "The command '/usr/bin/custom-tool' has been replaced by a script",
      );
      expect(finding.filePath, '/usr/bin/custom-tool');
      expect(
        finding.details,
        'Bourne-Again shell script, ASCII text executable',
      );
    });

    test('drops legacy known distro command script wrappers', () {
      final finding = RkhunterOutputParser.parseLegacyFinding(
        threatName:
            "The command '/usr/bin/ldd' has been replaced by a script: /usr/bin/ldd",
        filePath: 'Bourne-Again shell script, ASCII text executable',
      );

      expect(finding, isNull);
    });

    test('drops legacy non-finding warnings', () {
      final finding = RkhunterOutputParser.parseLegacyFinding(
        threatName: 'Checking for prerequisites               [ Warning ]',
        filePath: '(系统级检查)',
      );

      expect(finding, isNull);
    });
  });
}
