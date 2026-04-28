import 'package:flutter_test/flutter_test.dart';
import 'package:clamfox/data/clamav/clamscan_output_parser.dart';

void main() {
  group('ClamScanOutputParser.parse', () {
    test('returns empty result for empty input', () {
      final r = ClamScanOutputParser.parse('');
      expect(r.threats, isEmpty);
      expect(r.totalScanned, isNull);
      expect(r.totalInfected, isNull);
      expect(r.fileScannedIncrement, 0);
      expect(r.isEmpty, isTrue);
    });

    test('returns empty result for whitespace-only input', () {
      final r = ClamScanOutputParser.parse('   \n\n   \n');
      expect(r.isEmpty, isTrue);
    });

    test('parses single FOUND line', () {
      final r = ClamScanOutputParser.parse(
        '/home/user/eicar.com: Eicar-Test-Signature FOUND',
      );
      expect(r.threats, hasLength(1));
      expect(r.threats.first.filePath, '/home/user/eicar.com');
      expect(r.threats.first.threatName, 'Eicar-Test-Signature');
    });

    test('strips "FOUND" trailing token from threat name', () {
      final r = ClamScanOutputParser.parse(
        '/tmp/x.txt: Win.Trojan.Foo-1 FOUND',
      );
      expect(r.threats.first.threatName, 'Win.Trojan.Foo-1');
      expect(r.threats.first.threatName, isNot(contains('FOUND')));
    });

    test('parses multiple FOUND lines in one chunk', () {
      final input = [
        '/a/b/file1: Sig.A FOUND',
        '/a/b/file2: Sig.B FOUND',
        '/a/b/file3: Sig.C FOUND',
      ].join('\n');
      final r = ClamScanOutputParser.parse(input);
      expect(r.threats, hasLength(3));
      expect(r.threats.map((t) => t.threatName).toList(), [
        'Sig.A',
        'Sig.B',
        'Sig.C',
      ]);
    });

    test('counts per-file OK lines', () {
      final input = ['/a/x.txt: OK', '/a/y.txt: OK', '/a/z.txt: OK'].join('\n');
      final r = ClamScanOutputParser.parse(input);
      expect(r.fileScannedIncrement, 3);
      expect(r.threats, isEmpty);
    });

    test('counts Empty file lines as scanned', () {
      final r = ClamScanOutputParser.parse('/a/empty.txt: Empty file');
      expect(r.fileScannedIncrement, 1);
    });

    test('parses Scanned files summary', () {
      final r = ClamScanOutputParser.parse('Scanned files: 1234');
      expect(r.totalScanned, 1234);
    });

    test('parses Infected files summary', () {
      final r = ClamScanOutputParser.parse('Infected files: 7');
      expect(r.totalInfected, 7);
    });

    test('handles multi-line summary block', () {
      const input = '''
----------- SCAN SUMMARY -----------
Known viruses: 8688374
Engine version: 1.0.5
Scanned directories: 1
Scanned files: 42
Infected files: 2
Data scanned: 1.23 MB
''';
      final r = ClamScanOutputParser.parse(input);
      expect(r.totalScanned, 42);
      expect(r.totalInfected, 2);
    });

    test('mixed FOUND, OK and summary in one chunk', () {
      const input = '''
/h/a.txt: OK
/h/b.bin: Eicar-Test-Signature FOUND
/h/c.log: OK
Scanned files: 3
Infected files: 1
''';
      final r = ClamScanOutputParser.parse(input);
      expect(r.threats, hasLength(1));
      expect(r.threats.first.threatName, 'Eicar-Test-Signature');
      expect(r.fileScannedIncrement, 2);
      expect(r.totalScanned, 3);
      expect(r.totalInfected, 1);
    });

    test('ignores malformed FOUND lines without colon', () {
      final r = ClamScanOutputParser.parse('something FOUND but no colon');
      expect(r.threats, isEmpty);
    });

    test('ignores empty path or empty threat in FOUND', () {
      final r = ClamScanOutputParser.parse(': FOUND');
      expect(r.threats, isEmpty);
    });

    test('isEmpty true when no relevant data', () {
      final r = ClamScanOutputParser.parse('LibClamAV info: bla\nReading db');
      expect(r.isEmpty, isTrue);
    });
  });
}
