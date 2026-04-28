import 'package:clamfox/data/engines/chkrootkit_output_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChkrootkitOutputParser.parseLine', () {
    test('ignores missing helper diagnostics', () {
      expect(
        ChkrootkitOutputParser.parseLine("can't exec ./strings-static,"),
        isNull,
      );
      expect(
        ChkrootkitOutputParser.parseLine("not tested: can't exec ./ifpromisc"),
        isNull,
      );
    });

    test('ignores bare path lists from suspicious file sweeps', () {
      final finding = ChkrootkitOutputParser.parseLine(
        '/usr/lib/gio/modules/.keep /usr/lib/perl5/5.42/core_perl/.packlist /usr/lib/modules/6.19/build/.config',
      );
      expect(finding, isNull);
    });

    test('parses quiet mode infected checks', () {
      final finding = ChkrootkitOutputParser.parseLine(
        "Checking `bindshell'... INFECTED",
      );

      expect(finding, isNotNull);
      expect(finding!.threatName, 'bindshell 检测项报告 INFECTED');
      expect(finding.filePath, '(系统级检查)');
      expect(finding.details, "Checking `bindshell'... INFECTED");
    });

    test('parses possible malware lines', () {
      final finding = ChkrootkitOutputParser.parseLine(
        'INFECTED: Possible Malicious Linux.Xor.DDoS installed',
      );

      expect(finding, isNotNull);
      expect(
        finding!.threatName,
        'INFECTED: Possible Malicious Linux.Xor.DDoS installed',
      );
      expect(finding.filePath, '(系统级检查)');
    });

    test('parses warning lines with paths', () {
      final finding = ChkrootkitOutputParser.parseLine(
        'Warning: /etc/rc.d/init.d/network INFECTED',
      );

      expect(finding, isNotNull);
      expect(finding!.threatName, 'INFECTED');
      expect(finding.filePath, '/etc/rc.d/init.d/network');
      expect(finding.details, 'Warning: /etc/rc.d/init.d/network INFECTED');
    });

    test('parses suspect directories', () {
      final finding = ChkrootkitOutputParser.parseLine(
        'Suspect directory var/run/.tmp FOUND! Looking for sniffer logs',
      );

      expect(finding, isNotNull);
      expect(finding!.threatName, 'Suspect directory found');
      expect(finding.filePath, '/var/run/.tmp');
      expect(finding.details, 'Looking for sniffer logs');
    });

    test('drops legacy diagnostics', () {
      final finding = ChkrootkitOutputParser.parseLegacyFinding(
        threatName: "not tested: can't exec ./chkwtmp",
        filePath: '(系统级检查)',
      );

      expect(finding, isNull);
    });
  });
}
