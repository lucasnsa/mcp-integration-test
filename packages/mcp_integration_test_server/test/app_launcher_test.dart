import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_integration_test_server/src/app_launcher.dart';
import 'package:test/test.dart';

const _device = 'emulator-5554';

Future<String> _start(
  AppLauncher launcher, {
  String device = _device,
  int? port,
  bool adbForward = true,
  String mode = 'run',
}) => launcher.start(
  projectDir: Directory.systemTemp.path,
  device: device,
  target: 'integration_test/mcp_test.dart',
  mode: mode,
  port: port,
  dartDefines: const [],
  extraArgs: const [],
  adbForward: adbForward,
);

/// A launcher whose `adb` and `flutter` are fakes. `adb forward` binds the
/// host port like the real one, so port selection sees it as taken.
class _Fixture {
  _Fixture({bool spawnError = false, this.removeError = false}) {
    launcher = AppLauncher(
      startProcess: (executable, arguments, {workingDirectory}) async {
        if (spawnError) {
          throw ProcessException(executable, arguments, 'not found', 2);
        }
        final child = _FakeProcess(arguments);
        children.add(child);
        return child;
      },
      runCommand: (executable, arguments) async {
        calls.add([executable, ...arguments]);
        final port = int.parse(arguments[4].substring('tcp:'.length));
        if (arguments[3] == '--remove') {
          if (removeError) {
            return ProcessResult(0, 1, '', 'ADB unavailable');
          }
          final socket = forwards.remove(port);
          expect(socket, isNotNull, reason: 'only remove an owned forward');
          await socket!.close();
        } else {
          expect(arguments[3], '--no-rebind');
          forwards[port] = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            port,
          );
        }
        return ProcessResult(0, 0, '', '');
      },
    );
    addTearDown(() async {
      for (final socket in forwards.values) {
        await socket.close();
      }
    });
  }

  late final AppLauncher launcher;
  bool removeError;
  final calls = <List<String>>[];
  final forwards = <int, ServerSocket>{};
  final children = <_FakeProcess>[];
}

/// Records stdin and exits with code 0 when `q` is written to it.
class _FakeProcess implements Process {
  _FakeProcess(this.arguments);

  final List<String> arguments;
  final written = StringBuffer();
  final _exit = Completer<int>();
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  @override
  late final IOSink stdin = IOSink(_StdinConsumer(this));

  void finish(int code) {
    if (_exit.isCompleted) {
      return;
    }
    _exit.complete(code);
    _stdout.close();
    _stderr.close();
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    finish(-15);
    return true;
  }
}

class _StdinConsumer implements StreamConsumer<List<int>> {
  _StdinConsumer(this.process);

  final _FakeProcess process;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach((data) {
    final text = utf8.decode(data);
    process.written.write(text);
    if (text.contains('q')) {
      scheduleMicrotask(() => process.finish(0));
    }
  });

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'launch -> stop -> launch reuses an explicit port and removes the device forward',
    () async {
      final f = _Fixture();
      await _start(f.launcher);
      final port = f.launcher.port!;
      await f.launcher.stop();
      expect(f.forwards, isEmpty);
      expect(f.calls[1], [
        'adb',
        '-s',
        _device,
        'forward',
        '--remove',
        'tcp:$port',
      ]);
      await _start(f.launcher, port: port);
      expect(f.launcher.port, port);
      await f.launcher.stop();
      await f.launcher.stop();
      expect(f.calls, hasLength(4), reason: 'repeated stop is harmless');
    },
  );

  test('two launchers select different ports and stop independently', () async {
    final a = _Fixture();
    final b = _Fixture();
    await _start(a.launcher);
    await _start(b.launcher, device: 'emulator-5556');
    expect(a.launcher.port, isNot(b.launcher.port));
    for (final f in [a, b]) {
      expect(
        f.children.single.arguments,
        contains('--dart-define=MCP_IT_PORT=${f.launcher.port}'),
      );
    }
    await a.launcher.stop();
    expect(b.forwards, hasLength(1));
    expect(b.launcher.running, isTrue);
    await b.launcher.stop();
  });

  test(
    'occupied explicit port fails before ADB or Flutter is invoked',
    () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(taken.close);
      final f = _Fixture();
      await expectLater(
        _start(f.launcher, port: taken.port),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('port ${taken.port}'),
          ),
        ),
      );
      expect(f.calls, isEmpty);
      expect(f.children, isEmpty);
    },
  );

  test('stop cleans up even after the Flutter process exits', () async {
    final f = _Fixture();
    await _start(f.launcher);
    f.children.single.finish(1);
    await pumpEventQueue();
    expect(f.launcher.running, isFalse);
    await f.launcher.stop();
    expect(f.forwards, isEmpty);
  });

  test('spawn failure removes the forward', () async {
    final f = _Fixture(spawnError: true);
    await expectLater(_start(f.launcher), throwsA(isA<ProcessException>()));
    expect(f.forwards, isEmpty);
    expect(f.launcher.running, isFalse);
  });

  test('failed ADB cleanup is reported and can be retried', () async {
    final f = _Fixture(removeError: true);
    await _start(f.launcher);
    await expectLater(
      f.launcher.stop(),
      throwsA(
        isA<ProcessException>().having(
          (e) => e.message,
          'message',
          'ADB unavailable',
        ),
      ),
    );
    expect(f.forwards, hasLength(1));
    f.removeError = false;
    await f.launcher.stop();
    expect(f.forwards, isEmpty);
  });

  test('launch without ADB never creates or removes forwards', () async {
    final f = _Fixture();
    await _start(f.launcher, adbForward: false);
    await f.launcher.stop();
    expect(f.calls, isEmpty);
  });

  test('rejected second launch preserves the running session', () async {
    final f = _Fixture();
    await _start(f.launcher);
    final port = f.launcher.port;
    await expectLater(
      _start(f.launcher),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('already running'),
        ),
      ),
    );
    expect(f.launcher.port, port);
    expect(f.calls, hasLength(1));
    await f.launcher.stop();
  });

  test('hotRestart sends R to flutter run', () async {
    final f = _Fixture();
    await _start(f.launcher);
    expect(f.launcher.canHotRestart, isTrue);
    await f.launcher.hotRestart();
    expect(f.children.single.written.toString(), 'R');
    expect(f.launcher.running, isTrue);
    await f.launcher.stop();
  });

  test(
    'hotRestart is refused in test mode and after the process exits',
    () async {
      final f = _Fixture();
      await _start(f.launcher, mode: 'test');
      expect(f.launcher.canHotRestart, isFalse);
      await expectLater(f.launcher.hotRestart(), throwsA(isA<StateError>()));
      f.children.single.finish(0);
      await f.launcher.stop();

      await _start(f.launcher);
      f.children.last.finish(1);
      await pumpEventQueue();
      expect(f.launcher.canHotRestart, isFalse);
      await expectLater(f.launcher.hotRestart(), throwsA(isA<StateError>()));
      await f.launcher.stop();
    },
  );
}
