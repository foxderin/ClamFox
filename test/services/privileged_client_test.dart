import 'dart:io';

import 'package:clamfox/services/privileged_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrivilegedClient', () {
    test('isReady is false before start', () {
      final client = PrivilegedClient();
      expect(client.isReady, isFalse);
      expect(client.lastError, isNull);
    });

    test('start fails fast when helper binary is missing', () async {
      final client = PrivilegedClient();
      final ok = await client.start(
        binaryPath:
            '/tmp/clamfox-helper-does-not-exist-${DateTime.now().microsecondsSinceEpoch}',
      );
      expect(ok, isFalse);
      expect(client.isReady, isFalse);
      expect(client.lastError, isNotNull);
      expect(client.lastError, contains('特权模式服务未安装'));
    });

    test('request rejects when privileged service is not running', () async {
      final client = PrivilegedClient();
      await expectLater(
        client.request('detect', {'engine': 'rkhunter'}),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'openStream emits a single error when service is not running',
      () async {
        final client = PrivilegedClient();
        final result = client.openStream('scan', {'engine': 'clamav'});
        expect(result.id, isEmpty);
        await expectLater(result.stream, emitsError(isA<StateError>()));
      },
    );

    test('cancelStream is a no-op when service is not running', () async {
      final client = PrivilegedClient();
      await client.cancelStream('any-id'); // must not throw
    });

    test('openStream closes when helper returns a non-event error', () async {
      final client = PrivilegedClient();
      final process = await Process.start('sh', [
        '-c',
        'read line; '
            'echo \'{"id":"req-1","ok":true}\'; '
            'read line; '
            'echo \'{"id":"req-2","ok":false,"error":"invalid engine"}\'; '
            'sleep 1',
      ]);

      addTearDown(() async {
        await client.stop();
        process.kill();
      });

      final ok = await client.attachToProcess(
        process,
        handshakeTimeout: const Duration(seconds: 2),
      );
      expect(ok, isTrue);

      final result = client.openStream('scan', {'engine': 'bad'});
      await expectLater(
        result.stream,
        emitsError(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('invalid engine'),
          ),
        ),
      );
    });
  });
}
