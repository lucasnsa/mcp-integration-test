import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

typedef StartProcess =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });
typedef RunCommand =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Owns the Flutter test process, its recent stdout/stderr and the ADB
/// forward created for it.
class AppLauncher {
  AppLauncher({
    StartProcess startProcess = Process.start,
    RunCommand runCommand = Process.run,
  }) : _startProcess = startProcess,
       _runCommand = runCommand;

  static const _maxLogLines = 500;
  static const _quitTimeout = Duration(seconds: 5);

  final StartProcess _startProcess;
  final RunCommand _runCommand;
  final _logs = ListQueue<String>();
  Process? _child;
  bool _testMode = false;
  Future<String>? _starting;
  Future<void>? _finished;
  Future<void>? _stopping;
  ({String device, int port})? _forward;
  Map<String, Object?>? exit;

  /// Port of the in-app server for the last launch.
  int? port;

  bool get running => _child != null && exit == null;

  /// `flutter run` reads hot restart (`R`) from stdin; `flutter test` does not.
  bool get canHotRestart => running && !_testMode;

  /// Asks `flutter run` for a hot restart: main() runs again in a new isolate.
  Future<void> hotRestart() async {
    if (!canHotRestart) {
      throw StateError(
        'Hot restart needs an app started by app_launch in mode "run".',
      );
    }
    final stdin = _child!.stdin;
    stdin.write('R');
    await stdin.flush();
  }

  List<String> recentLogs(int lines) {
    final start = _logs.length - lines;
    return _logs.skip(start < 0 ? 0 : start).toList();
  }

  /// Starts Flutter on [port], or on a free loopback port when it is null.
  Future<String> start({
    required String projectDir,
    required String device,
    required String target,
    required String mode,
    required int? port,
    required List<String> dartDefines,
    required List<String> extraArgs,
    required bool adbForward,
  }) async {
    if (running || _starting != null || _stopping != null) {
      throw StateError('An app is already running. Call app_stop first.');
    }
    // Clean up after a process that already exited (e.g. its ADB forward).
    await stop();
    _starting = _start(
      projectDir: projectDir,
      device: device,
      target: target,
      testMode: mode == 'test',
      requestedPort: port,
      dartDefines: dartDefines,
      extraArgs: extraArgs,
      adbForward: adbForward,
    );
    try {
      return await _starting!;
    } finally {
      _starting = null;
    }
  }

  Future<String> _start({
    required String projectDir,
    required String device,
    required String target,
    required bool testMode,
    required int? requestedPort,
    required List<String> dartDefines,
    required List<String> extraArgs,
    required bool adbForward,
  }) async {
    final port = this.port = await selectPort(requestedPort);
    if (adbForward) {
      // Do not replace a mapping owned by another session if port selection
      // races.
      await _run('adb', [
        '-s',
        device,
        'forward',
        '--no-rebind',
        'tcp:$port',
        'tcp:$port',
      ]);
      _forward = (device: device, port: port);
    }

    final defines = [
      '--dart-define=MCP_IT_PORT=$port',
      for (final define in dartDefines) '--dart-define=$define',
    ];
    final args = [
      if (testMode) ...[
        'test',
        target,
        '-d',
        device,
      ] else ...[
        'run',
        '-d',
        device,
        '-t',
        target,
      ],
      ...defines,
      ...extraArgs,
    ];

    await _finished;
    _logs.clear();
    exit = null;
    try {
      final child = await _startProcess(
        'flutter',
        args,
        workingDirectory: projectDir,
      );
      _child = child;
      _testMode = testMode;
      // A process can close its stdin before we try to quit it.
      unawaited(child.stdin.done.then<void>((_) {}, onError: (Object _) {}));
      _finished = Future.wait([
        _readLogs(child.stdout, ''),
        _readLogs(child.stderr, '[stderr] '),
        child.exitCode.then((code) {
          exit = {
            'code': code < 0 ? null : code,
            'signal': switch (code) {
              -2 => 'SIGINT',
              -9 => 'SIGKILL',
              -15 => 'SIGTERM',
              < 0 => 'SIG${-code}',
              _ => null,
            },
          };
        }),
      ]).then((_) {});
    } on ProcessException catch (error) {
      exit = {'error': error.message};
      _addLog('[spawn] ${error.message}');
      await _removeForward();
      rethrow;
    }
    return 'flutter ${args.join(' ')}';
  }

  Future<void> _run(String executable, List<String> args) async {
    final result = await _runCommand(executable, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  Future<void> _removeForward() async {
    final forward = _forward;
    if (forward == null) {
      return;
    }
    await _run('adb', [
      '-s',
      forward.device,
      'forward',
      '--remove',
      'tcp:${forward.port}',
    ]);
    _forward = null;
  }

  Future<void> _readLogs(Stream<List<int>> stream, String tag) async {
    await for (final line
        in stream
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      if (line.trim().isNotEmpty) {
        _addLog('$tag$line');
      }
    }
  }

  void _addLog(String line) {
    if (_logs.length == _maxLogLines) {
      _logs.removeFirst();
    }
    _logs.addLast(line);
  }

  /// Stops the process and removes its ADB forward, even when the process
  /// already exited. A failed removal is rethrown and retried on the next
  /// call.
  Future<void> stop() async {
    if (_stopping case final stopping?) {
      return stopping;
    }
    _stopping = _stop();
    try {
      await _stopping!;
    } finally {
      _stopping = null;
    }
  }

  Future<void> _stop() async {
    try {
      await _starting;
    } catch (_) {
      // The launch call reports the failure.
    }
    try {
      await _stopProcess();
    } finally {
      await _removeForward();
    }
  }

  Future<void> _stopProcess() async {
    final child = _child;
    final finished = _finished;
    if (child == null || finished == null) {
      return;
    }

    if (running && !_testMode) {
      try {
        child.stdin.write('q');
        await child.stdin.flush();
      } on Exception {
        // The process may have closed stdin already.
      }
    }
    try {
      // In test mode, let the integration test report its real exit code
      // after the in-app shutdown command.
      await finished.timeout(_quitTimeout);
    } on TimeoutException {
      child.kill(ProcessSignal.sigterm);
      try {
        await finished.timeout(_quitTimeout);
      } on TimeoutException {
        child.kill(ProcessSignal.sigkill);
        await finished;
      }
    } finally {
      _child = null;
      _finished = null;
    }
  }
}

/// Returns a free loopback port, or checks that [port] is free.
Future<int> selectPort(int? port) async {
  if (port != null && (port < 1 || port > 65535)) {
    throw ArgumentError('Port must be an integer between 1 and 65535.');
  }
  final ServerSocket socket;
  try {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port ?? 0);
  } on SocketException catch (error) {
    throw StateError(
      'Cannot use local port ${port ?? '(automatically selected)'} '
      '(${error.osError?.message ?? error.message}). '
      'Choose another port or omit port to select a free one.',
    );
  }
  final selected = socket.port;
  await socket.close();
  return selected;
}
