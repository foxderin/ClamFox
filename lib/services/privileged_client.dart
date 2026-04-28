import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Long-lived RPC client for the privileged-mode service.
///
/// One pkexec authentication launches `clamfox-helper` as root; thereafter
/// the main process talks to it via stdio JSON Lines, so subsequent scans /
/// updates / installs do not re-prompt for a password.
///
/// All public methods are safe to call when [isReady] is false — they will
/// throw `StateError('特权模式服务未运行')`.
class PrivilegedClient extends ChangeNotifier {
  static const String defaultBinaryPath = '/usr/lib/clamfox/clamfox-helper';

  Process? _proc;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final Map<String, StreamController<Map<String, dynamic>>> _streams = {};
  int _seq = 0;
  String? _lastError;

  bool get isReady => _proc != null;
  String? get lastError => _lastError;

  String _nextId() => 'req-${++_seq}';

  /// Spawn the helper via pkexec and complete the ping handshake.
  /// Returns false on any failure (auth denied, helper crash, timeout); the
  /// reason is stashed in [lastError] for the UI.
  Future<bool> start({
    String binaryPath = defaultBinaryPath,
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) async {
    if (_proc != null) return true;

    if (!File(binaryPath).existsSync()) {
      _lastError = '特权模式服务未安装 ($binaryPath)。请在设置页点击「安装服务」';
      notifyListeners();
      return false;
    }

    Process p;
    try {
      p = await Process.start('pkexec', [binaryPath]);
    } on ProcessException catch (e) {
      _lastError = '启动失败: ${e.message}';
      notifyListeners();
      return false;
    }
    return attachToProcess(p, handshakeTimeout: handshakeTimeout);
  }

  /// Test seam: attach to an already-spawned helper-like process and run the
  /// ping handshake. Production code uses [start]; tests can drive this with
  /// a fake subprocess that talks the JSON Lines protocol.
  @visibleForTesting
  Future<bool> attachToProcess(
    Process p, {
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) async {
    if (_proc != null) return true;
    _proc = p;
    _stdoutSub = p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (Object e, StackTrace _) {
            debugPrint('[helper-stdout] $e');
          },
        );
    _stderrSub = p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => debugPrint('[helper-stderr] $l'));
    // pkexec may exit synchronously when the binary is missing or the user
    // cancels the auth dialog. Without this catchError, the next stdin write
    // raises a broken-pipe SocketException that propagates as an unhandled
    // zone error and crashes the app.
    unawaited(
      p.stdin.done.catchError((Object e) {
        debugPrint('[helper-stdin] $e');
      }),
    );
    unawaited(
      p.exitCode.then((code) {
        if (identical(_proc, p)) _onClosed();
      }),
    );

    try {
      final reply = await request('ping').timeout(handshakeTimeout);
      if (reply['ok'] != true) {
        _lastError = '特权模式服务握手失败: ${reply['error'] ?? '未知错误'}';
        await stop();
        return false;
      }
    } catch (e) {
      _lastError = '特权模式服务握手失败: $e';
      await stop();
      return false;
    }

    _lastError = null;
    notifyListeners();
    return true;
  }

  /// Send a synchronous request, await `{id, ok, data?, error?}`.
  Future<Map<String, dynamic>> request(
    String type, [
    Map<String, dynamic> args = const {},
  ]) {
    if (_proc == null) {
      return Future.error(StateError('特权模式服务未运行'));
    }
    final id = _nextId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final ok = _writeLine({'id': id, 'type': type, ...args});
    if (!ok) {
      _pending.remove(id);
      return Future.error(StateError('特权模式服务未运行'));
    }
    return completer.future;
  }

  /// Start a streaming request and receive `{id, event, ...}` events until
  /// `event: finished`. Cancelling the returned stream sends a `cancel`
  /// command to the helper.
  ///
  /// Returns the stream id (so callers can issue an explicit `cancel`) and
  /// the event stream.
  ({String id, Stream<Map<String, dynamic>> stream}) openStream(
    String type, [
    Map<String, dynamic> args = const {},
  ]) {
    if (_proc == null) {
      final ctl = StreamController<Map<String, dynamic>>();
      ctl.addError(StateError('特权模式服务未运行'));
      unawaited(ctl.close());
      return (id: '', stream: ctl.stream);
    }
    final id = _nextId();
    final controller = StreamController<Map<String, dynamic>>();
    controller.onCancel = () {
      // Stream subscription cancelled → tell helper to stop the underlying
      // process (best-effort).
      if (_streams.remove(id) != null && _proc != null) {
        unawaited(
          request('cancel', {
            'scanId': id,
          }).catchError((Object _) => <String, dynamic>{}),
        );
      }
    };
    _streams[id] = controller;
    final ok = _writeLine({'id': id, 'type': type, ...args});
    if (!ok) {
      _streams.remove(id);
      controller.addError(StateError('特权模式服务未运行'));
      unawaited(controller.close());
    }
    return (id: id, stream: controller.stream);
  }

  /// Explicitly cancel an in-flight stream by id (alternative to subscription
  /// cancel — useful when a third party needs to stop a scan).
  Future<void> cancelStream(String streamId) async {
    if (_proc == null) return;
    try {
      await request('cancel', {'scanId': streamId});
    } catch (_) {
      // ignore — helper may have already gone away
    }
  }

  /// Polite shutdown: send shutdown command, wait for exit, fall back to
  /// SIGKILL after a timeout.
  Future<void> stop() async {
    final p = _proc;
    if (p == null) return;
    try {
      _writeLine({'id': _nextId(), 'type': 'shutdown'});
      await p.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          try {
            p.kill(ProcessSignal.sigkill);
          } catch (_) {}
          return -1;
        },
      );
    } catch (_) {
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (_) {}
    } finally {
      _onClosed();
    }
  }

  bool _writeLine(Map<String, dynamic> obj) {
    final p = _proc;
    if (p == null) return false;
    try {
      p.stdin.writeln(jsonEncode(obj));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    Map<String, dynamic> msg;
    try {
      final parsed = jsonDecode(trimmed);
      if (parsed is! Map) return;
      msg = Map<String, dynamic>.from(parsed);
    } on FormatException {
      debugPrint('[helper] non-JSON line: $trimmed');
      return;
    }
    final id = msg['id']?.toString();
    if (id == null) return;

    if (msg.containsKey('event')) {
      final controller = _streams[id];
      if (controller == null) return;
      controller.add(msg);
      if (msg['event'] == 'finished') {
        unawaited(controller.close());
        _streams.remove(id);
      }
    } else {
      final stream = _streams.remove(id);
      if (stream != null) {
        if (msg['ok'] == false) {
          stream.addError(
            StateError(msg['error']?.toString() ?? 'helper request failed'),
          );
        }
        unawaited(stream.close());
        return;
      }
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(msg);
      }
    }
  }

  void _onClosed() {
    final p = _proc;
    if (p == null) return;
    _proc = null;
    unawaited(_stdoutSub?.cancel());
    unawaited(_stderrSub?.cancel());
    _stdoutSub = null;
    _stderrSub = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('特权模式服务已断开'));
      }
    }
    _pending.clear();
    for (final s in _streams.values) {
      s.addError(StateError('特权模式服务已断开'));
      unawaited(s.close());
    }
    _streams.clear();
    try {
      p.kill();
    } catch (_) {}
    notifyListeners();
  }
}
