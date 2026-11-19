import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Owns the Flutter test process and its recent stdout/stderr.
class AppLauncher {
  static const _maxLogLines = 500;
  static const _quitTimeout = Duration(seconds: 5);

  final _logs = ListQueue<String>();
  Process? _child;
  bool _testMode = false;
  Future<String>? _starting;
  Future<void>? _finished;
  Future<void>? _stopping;
  Map<String, Object?>? exit;

  bool get running => _child != null && exit == null;

  List<String> recentLogs(int lines) {
    // Match the old server's logs.slice(-lines), including zero.
    final start = lines > 0 ? _logs.length - lines : -lines;
    return _logs.skip(start < 0 ? 0 : start).toList();
  }

  Future<String> start({
    required String projectDir,
    required String device,
    required String target,
    required String mode,
    required int port,
    required List<String> dartDefines,
    required List<String> extraArgs,
    required bool adbForward,
  }) async {
    if (running || _starting != null || _stopping != null) {
      throw StateError('An app is already running. Call app_stop first.');
    }
    _starting = _start(
      projectDir: projectDir,
      device: device,
      target: target,
      testMode: mode == 'test',
      port: port,
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
    required int port,
    required List<String> dartDefines,
    required List<String> extraArgs,
    required bool adbForward,
  }) async {
    if (adbForward) {
      final result = await Process.run('adb', [
        '-s',
        device,
        'forward',
        'tcp:$port',
        'tcp:$port',
      ]);
      if (result.exitCode != 0) {
        throw ProcessException('adb', [], '${result.stderr}', result.exitCode);
      }
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
      final child = await Process.start(
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
      rethrow;
    }
    return 'flutter ${args.join(' ')}';
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
    } on ProcessException {
      return; // The launch call reports the failure.
    }
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
