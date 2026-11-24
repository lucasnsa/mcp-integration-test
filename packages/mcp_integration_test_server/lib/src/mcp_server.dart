import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

import 'package:mcp_integration_test_protocol/mcp_integration_test_protocol.dart';
import 'app_client.dart';
import 'app_launcher.dart';
import 'session_recorder.dart';
import 'test_exporter.dart';

const _json = JsonEncoder.withIndent('  ');
const _shutdownTimeout = Duration(seconds: 5);
const _maxSafeInteger = 9007199254740991;

IntegerSchema _integer({String? description, int minimum = -_maxSafeInteger}) =>
    Schema.int(
      description: description,
      minimum: minimum,
      maximum: _maxSafeInteger,
    );

final _finderFields = <String, Schema>{
  'text': Schema.string(description: 'Exact text of a Text / TextField'),
  'textContaining': Schema.string(
    description: 'Substring of a Text / TextField',
  ),
  'key': Schema.string(
    description: 'Value of a ValueKey<String>, e.g. Key("login")',
  ),
  'type': Schema.string(
    description:
        'Widget runtimeType, e.g. "FilledButton", "TextField", "ListView"',
  ),
  'tooltip': Schema.string(),
  'semanticsLabel': Schema.string(),
  'includeOffstage': Schema.bool(
    description: 'Also match offstage widgets (default false)',
  ),
  'index': _integer(
    minimum: 0,
    description: 'Which match to use when several (default 0)',
  ),
};

ObjectSchema _finderSchema({
  String description =
      'Matches widgets; all given fields must match the same widget. Prefer key, then text.',
}) => Schema.object(
  description: description,
  properties: {
    ..._finderFields,
    'within': Schema.object(
      properties: _finderFields,
      description:
          'Only match inside widgets matching this finder (same fields, no nesting)',
    ),
  },
);

final _finder = {'finder': _finderSchema()};
final _settle = <String, Schema>{
  'settle': Schema.bool(
    description:
        'Wait for animations to finish after the action (default true)',
  ),
  'settleTimeoutMs': _integer(
    description: 'Max wait for settling (default 3000)',
  ),
};
final _shotFields = <String, Schema>{
  'shot': Schema.string(
    description:
        'Absolute .png path: after the action, save a screenshot there (evidence) in the same call',
  ),
  'shotImage': Schema.bool(
    description:
        'Also return that screenshot as an image (default false: saved only)',
  ),
};
final _submit = Schema.bool(
  description: 'Send the "done" keyboard action afterwards',
);

final class IntegrationTestMcpServer extends MCPServer with ToolsSupport {
  IntegrationTestMcpServer()
    : super.fromStreamChannel(
        stdioChannel(input: stdin, output: stdout),
        implementation: Implementation(
          name: 'flutter-integration-test',
          version: '0.2.0',
        ),
      ) {
    _client = AppClient(
      Platform.environment['MCP_IT_URL'] ?? 'http://127.0.0.1:$_defaultPort',
    );
    _registerTools();
  }

  final _defaultPort =
      int.tryParse(Platform.environment['MCP_IT_PORT'] ?? '') ??
      defaultCommandPort;
  final _shotWidth =
      num.tryParse(Platform.environment['MCP_IT_SHOT_WIDTH'] ?? '') ?? 360;
  final _envFile = Platform.environment['MCP_IT_ENV_FILE'];
  final _launcher = AppLauncher();
  final _recorder = SessionRecorder();
  String? _lastProjectDir;
  String? _lastDevice;
  late AppClient _client;
  AppClient? _launchedClient;
  bool _launching = false;
  Future<CallToolResult>? _stopping;

  /// Expectations recorded before hot restarts (lost with the old isolate).
  var _carried = (passed: 0, failures: <String>[]);

  /// On MCP disconnect, clean up only a Flutter process we started.
  Future<void> closeApp() async {
    final launchedClient = _launchedClient;
    if (_stopping case final stopping?) {
      await stopping;
    } else if (_launcher.running && launchedClient != null) {
      await _shutdownApp(launchedClient);
    } else {
      await _launcher.stop();
    }
  }

  void _registerTools() {
    _tool(
      'app_launch',
      'Build and start the Flutter app\'s MCP test entry point (e.g. '
          'integration_test/mcp_test.dart) on a device, then wait until it '
          'accepts commands. First build can take minutes.',
      {
        'projectDir': Schema.string(
          description: 'Absolute path of the Flutter project',
        ),
        'device': Schema.string(
          description:
              'Device id from `flutter devices` (e.g. emulator-5554, linux, <ios simulator id>)',
        ),
        'target': Schema.string(
          description: 'Entry point (default integration_test/mcp_test.dart)',
        ),
        'mode': UntitledSingleSelectEnumSchema(
          values: const ['run', 'test'],
          description:
              '"run" = flutter run (default); "test" = flutter test '
              '(official integration_test flow; non-zero exit when an expect fails)',
        ),
        'port': Schema.int(
          minimum: 1,
          maximum: 65535,
          description:
              'In-app server port (automatically selects a free local port when omitted)',
        ),
        'dartDefines': Schema.list(
          items: Schema.string(),
          description: 'Extra --dart-define values, KEY=VALUE',
        ),
        'extraArgs': Schema.list(
          items: Schema.string(),
          description: 'Extra flutter args, e.g. ["--flavor","dev"]',
        ),
        'adbForward': Schema.bool(
          description:
              'Run `adb forward` for the port (needed for Android devices/emulators)',
        ),
        'timeoutSec': _integer(
          description: 'Max wait for the first build (default 600)',
        ),
      },
      _launch,
      required: const ['projectDir', 'device'],
    );
    _tool(
      'app_connect',
      'Point at an already-running MCP test build (started manually). For '
          'Android run `adb forward tcp:PORT tcp:PORT` first.',
      {
        'port': _integer(),
        'host': Schema.string(description: 'default 127.0.0.1'),
      },
      (args) async {
        final host = args['host'] as String? ?? '127.0.0.1';
        final port = (args['port'] as num?)?.toInt() ?? _defaultPort;
        final client = _client = AppClient('http://$host:$port');
        _carried = (passed: 0, failures: <String>[]);
        return await client.health()
            ? _text({'connected': true, 'url': client.baseUrl})
            : _fail('Nothing answering at ${client.baseUrl}');
      },
    );
    _tool(
      'app_logs',
      'Last lines of the flutter process output (build errors, app prints).',
      {'lines': _integer(minimum: 0)},
      (args) => _text({
        'running': _launcher.running,
        'exit': _launcher.exit,
        'logs': _launcher.recentLogs((args['lines'] as num?)?.toInt() ?? 60),
      }),
    );
    _tool(
      'app_stop',
      'End the session: reports expectation results, shuts the in-app server down '
          'and stops the flutter process. With flutter test mode, unacknowledged '
          'app errors (overflow, exceptions) fail the run unless ignoreErrors is true.',
      {
        'ignoreErrors': Schema.bool(
          description: 'Do not fail the run because of recorded app errors',
        ),
      },
      (args) => _stopApp(ignoreErrors: args['ignoreErrors'] == true),
    );
    _tool(
      'app_restart',
      'Reset the app to its initial screen with fresh state. Hot restart when '
          'it was started by app_launch in mode "run"; otherwise a soft restart '
          '(widget tree rebuilt and main() re-run; static/global state is kept). '
          'Expectation counters are preserved.',
      {
        'timeoutSec': _integer(
          minimum: 1,
          description: 'Max wait for the app to answer again (default 60)',
        ),
      },
      (args) async {
        final result = await _restart(args);
        if (result.isError != true) {
          _recorder.record('app_restart', const {});
        }
        return result;
      },
      shots: true,
    );
    _registerRecordingTools();

    _forward(
      CommandMethod.status,
      'Platform, logical screen size, pixel ratio and expectation counters.',
      {},
      name: 'app_status',
      map: (result) => {
        ...result,
        'expectations': _withCarried(
          result['expectations'] as Map<String, Object?>,
        ),
      },
    );
    _forward(
      CommandMethod.snapshot,
      'Text description of what is on screen: visible Text, inputs, buttons, switches… '
      'with key, text, bounds [left, top, width, height] and tappable. '
      'Call this first and after navigation.',
      {'maxNodes': _integer(description: 'default 300')},
    );
    _forward(
      CommandMethod.find,
      'Count and describe widgets matching a finder.',
      _finder,
    );
    _forward(
      CommandMethod.getText,
      'Text content of the matched widget (Text / TextField), including descendants.',
      _finder,
    );
    _tool(
      'screenshot',
      'PNG screenshot of the app (debug/profile builds). Returns the image; '
          'with `path` it is also saved to that file (evidence).',
      {
        'maxWidth': Schema.num(description: 'Max width in px (default 800)'),
        'path': Schema.string(
          description: 'Absolute path of a .png file to save the screenshot to',
        ),
      },
      (args) async {
        final path = args.remove('path') as String?;
        final result = await _screenshot(_client, args);
        final data = result['pngBase64'] as String;
        if (path != null && path.isNotEmpty) {
          await _saveScreenshot(path, data);
        }
        return CallToolResult(
          content: [
            ImageContent(data: data, mimeType: 'image/png'),
            if (path != null && path.isNotEmpty)
              TextContent(text: 'saved $path'),
            TextContent(text: '${result['width']}x${result['height']}'),
          ],
        );
      },
    );

    _forward(CommandMethod.tap, 'Tap the matched widget.', {
      ..._finder,
      ..._settle,
    }, shots: true);
    _forward(CommandMethod.longPress, 'Long-press the matched widget.', {
      ..._finder,
      ..._settle,
    }, shots: true);
    _forward(CommandMethod.doubleTap, 'Double-tap the matched widget.', {
      ..._finder,
      ..._settle,
    }, shots: true);
    _forward(
      CommandMethod.tapAt,
      'Tap at logical-pixel coordinates (use bounds from snapshot).',
      {'x': Schema.num(), 'y': Schema.num(), ..._settle},
      required: const ['x', 'y'],
      shots: true,
    );
    _forward(
      CommandMethod.enterText,
      'Type text into the matched TextField (replaces its content).',
      {..._finder, 'text': Schema.string(), 'submit': _submit, ..._settle},
      required: const ['finder', 'text'],
      shots: true,
    );
    _tool(
      'enterEnv',
      'Type the value of a variable from the test env file into the matched TextField '
          '(replaces its content). Use for secrets (login, password): the value '
          'is never returned, only its length. Names come from `envKeys`.',
      {
        ..._finder,
        'name': Schema.string(
          description: 'Variable name in the env file, e.g. E2E_LOGIN_PASSWORD',
        ),
        'submit': _submit,
        ..._settle,
      },
      _enterEnv,
      required: const ['finder', 'name'],
      shots: true,
    );
    _tool(
      'envKeys',
      'Names (never values) of the variables available to enterEnv.',
      {},
      (_) async => _text({'keys': (await _readEnv()).keys.toList()}),
    );
    _forward(
      CommandMethod.drag,
      'Drag the matched widget by (dx, dy) logical px. Negative dy scrolls content up.',
      {..._finder, 'dx': Schema.num(), 'dy': Schema.num(), ..._settle},
      required: const ['finder', 'dx', 'dy'],
      shots: true,
    );
    _forward(
      CommandMethod.fling,
      'Fling the matched widget.',
      {
        ..._finder,
        'dx': Schema.num(),
        'dy': Schema.num(),
        'speed': Schema.num(),
        ..._settle,
      },
      required: const ['finder', 'dx', 'dy'],
      shots: true,
    );
    _forward(
      CommandMethod.scrollUntilVisible,
      'Scroll a scrollable until the target widget is built and visible.',
      {
        ..._finder,
        'scrollable': _finderSchema(
          description: 'Scrollable to drag (default: first Scrollable)',
        ),
        'delta': Schema.num(
          description:
              'Vertical drag per step in px; negative reveals items below (default -200)',
        ),
        'dx': Schema.num(description: 'Horizontal drag per step'),
        'maxScrolls': _integer(),
        ..._settle,
      },
      timeout: const Duration(minutes: 2),
      shots: true,
    );
    _forward(
      CommandMethod.pressBack,
      'Simulate the system back button / pop route.',
      {},
      shots: true,
    );
    _forward(
      CommandMethod.sendKey,
      'Send a keyboard key.',
      {
        'key': UntitledSingleSelectEnumSchema(
          values: const [
            'enter',
            'tab',
            'escape',
            'backspace',
            'space',
            'arrowUp',
            'arrowDown',
            'arrowLeft',
            'arrowRight',
          ],
        ),
        ..._settle,
      },
      required: const ['key'],
      shots: true,
    );
    _forward(CommandMethod.pump, 'Advance the frame clock by N ms.', {
      'ms': _integer(),
    });
    _forward(
      CommandMethod.pumpAndSettle,
      'Pump until no animation is running; errors on endless animations.',
      {'timeoutMs': _integer()},
    );

    _forward(
      CommandMethod.waitFor,
      'Wait until a widget appears (or disappears with absent=true).',
      {
        ..._finder,
        'absent': Schema.bool(),
        'timeoutMs': _integer(description: 'default 10000'),
      },
      timeout: const Duration(minutes: 10),
      shots: true,
    );
    _forward(
      CommandMethod.expect,
      'Record an assertion (integration_test `expect`). Failures do not stop the '
      'session; they are listed by test_results and fail the test run on app_stop.',
      {
        ..._finder,
        'exists': Schema.bool(description: 'Default: must exist'),
        'count': _integer(description: 'Exact number of matches'),
        'text': Schema.string(description: 'Text the widget must contain'),
      },
    );
    _forward(
      CommandMethod.errors,
      'List errors raised inside the app (RenderFlex overflow, build/layout/gesture '
      'exceptions) with count, command that triggered them and stack. Also returned '
      'as appErrors in any command response when new ones appear.',
      {
        'clear': Schema.bool(
          description:
              'Acknowledge and clear them (so they do not fail the run)',
        ),
      },
      name: 'app_errors',
    );
    _forward(
      CommandMethod.results,
      'Passed/failed expectation totals and failure messages.',
      {},
      name: 'test_results',
      map: _withCarried,
    );
  }

  void _registerRecordingTools() {
    _tool(
      'recording_start',
      'Start recording the session: from now on successful actions, waits, '
          'expectations and app_restart are kept so export_test can turn them '
          'into a regular integration_test file. Clears any previous recording.',
      {},
      (_) {
        _recorder.start();
        return _text({'recording': true});
      },
    );
    _tool(
      'recording_stop',
      'Stop recording. The recorded steps are kept for export_test.',
      {},
      (_) {
        _recorder.stop();
        return _text({
          'recording': false,
          'steps': _recorder.steps.length,
          'tools': [for (final step in _recorder.steps) step.tool],
        });
      },
    );
    _tool(
      'export_test',
      'Write the recorded steps as integration_test/<name>_test.dart: one '
          'testWidgets that replays them with the plain flutter_test API, so '
          'it runs with `flutter test` in CI without MCP. Expectations that '
          'failed while recording are left as comments; enterEnv values are '
          'read with String.fromEnvironment (never written to the file).',
      {
        'name': Schema.string(
          description: 'snake_case file name, e.g. "login_flow"',
        ),
        'projectDir': Schema.string(
          description:
              'Absolute path of the Flutter project (default: the one from app_launch)',
        ),
        'description': Schema.string(
          description: 'Name of the generated testWidgets (default: name)',
        ),
        'imports': Schema.list(
          items: Schema.string(),
          description:
              'Imports for the app setup, optionally prefixed: '
              '["package:my_app/main.dart as app"] (the default) or '
              '["test_app.dart"] for a file next to the test',
        ),
        'appMain': Schema.string(
          description:
              'Dart statements that start the app, like the mcpIntegrationTest '
              'callback (default "app.main();")',
        ),
        'overwrite': Schema.bool(
          description: 'Replace an existing file (default false)',
        ),
      },
      _exportTest,
      required: const ['name'],
    );
  }

  Future<CallToolResult> _exportTest(Map<String, Object?> args) async {
    final steps = _recorder.steps;
    if (steps.isEmpty) {
      return _fail(
        'Nothing recorded. Call recording_start, drive the app, then export_test.',
      );
    }
    final name = args['name'] as String;
    final fileName = testFileName(name);
    final projectDir = args['projectDir'] as String? ?? _lastProjectDir;
    if (projectDir == null || projectDir.isEmpty) {
      return _fail('Pass projectDir: no app was started with app_launch.');
    }
    final pubspec = File('$projectDir/pubspec.yaml');
    if (!await pubspec.exists()) {
      return _fail('No pubspec.yaml in $projectDir');
    }

    var imports = (args['imports'] as List?)?.cast<String>();
    var appMain = args['appMain'] as String?;
    if (imports == null && appMain == null) {
      final package = RegExp(
        r'^name:\s*(\S+)',
        multiLine: true,
      ).firstMatch(await pubspec.readAsString())?.group(1);
      if (package == null) {
        return _fail('Could not read the package name from ${pubspec.path}');
      }
      imports = ['package:$package/main.dart as app'];
    }
    final relativePath = 'integration_test/$fileName';
    final device = _lastDevice ?? '<device>';
    final source = generateIntegrationTest(
      steps,
      ExportOptions(
        description: args['description'] as String? ?? name,
        imports: imports ?? const [],
        appMain: appMain ?? 'app.main();',
        runCommand: 'flutter test $relativePath -d $device',
      ),
    );

    final file = File('$projectDir/$relativePath');
    if (await file.exists() && args['overwrite'] != true) {
      return _fail('${file.path} already exists. Pass overwrite: true.');
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(source);
    final formatted = await _formatDart(file.path);
    return _text({
      'path': file.path,
      'formatted': formatted,
      'steps': steps.length,
      'skippedExpectations': steps.where((s) => s.failure != null).length,
      'run': 'flutter test $relativePath -d $device',
    });
  }

  /// Runs `dart format` on [path] with the SDK running this server. Best
  /// effort: the file is valid Dart either way.
  Future<bool> _formatDart(String path) async {
    final dart = Platform.resolvedExecutable;
    // A compiled server binary is not the Dart SDK: skip rather than run it.
    if (!RegExp(r'dart(\.exe)?$').hasMatch(dart)) {
      return false;
    }
    try {
      final result = await Process.run(dart, ['format', path]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void _tool(
    String name,
    String description,
    Map<String, Schema> fields,
    FutureOr<CallToolResult> Function(Map<String, Object?>) run, {
    List<String> required = const [],
    bool shots = false,
  }) {
    final schema = Schema.object(
      properties: {...fields, if (shots) ..._shotFields},
      required: required.isEmpty ? null : required,
    );
    registerTool(
      Tool(name: name, description: description, inputSchema: schema),
      (request) async {
        final args = _knownArguments(schema, request.arguments ?? const {});
        final errors = schema.validate(args);
        if (errors.isNotEmpty) {
          return _fail(errors.map((error) => error.toErrorString()).join('\n'));
        }
        final path = args.remove('shot') as String?;
        final withImage = args.remove('shotImage') == true;
        final app = _client;
        CallToolResult result;
        try {
          result = await run(args);
        } catch (error) {
          result = _fail(error);
        }
        if (path != null && path.isNotEmpty) {
          result.content.addAll(await _captureShot(app, path, withImage));
        }
        return result;
      },
      // The previous server stripped unknown keys, even in nested finders.
      validateArguments: false,
    );
  }

  Map<String, Object?> _knownArguments(
    ObjectSchema schema,
    Map<String, Object?> args,
  ) => {
    for (final field in schema.properties!.entries)
      if (args.containsKey(field.key))
        field.key: switch (args[field.key]) {
          final Map<String, Object?> value
              when field.value.type == JsonType.object =>
            _knownArguments(field.value as ObjectSchema, value),
          final value => value,
        },
  };

  void _forward(
    CommandMethod method,
    String description,
    Map<String, Schema> fields, {
    String? name,
    List<String>? required,
    Duration timeout = const Duration(minutes: 1),
    bool shots = false,
    Map<String, Object?> Function(Map<String, Object?> result)? map,
  }) {
    _tool(
      name ?? method.name,
      description,
      fields,
      (args) async {
        final body = await _client.call(method, args, timeout);
        final result = body['result'];
        _recorder.record(
          method.name,
          args,
          failure: result is Map && result['ok'] == false
              ? '${result['message']}'
              : null,
        );
        return _textWithAppErrors(body, map: map);
      },
      required:
          required ??
          (fields.containsKey('finder') ? const ['finder'] : const []),
      shots: shots,
    );
  }

  Future<CallToolResult> _launch(Map<String, Object?> args) async {
    if (_stopping != null) {
      return _fail('The app is stopping. Try app_launch again.');
    }
    if (_launching) {
      return _fail('An app is already launching. Call app_stop first.');
    }
    _launching = true;
    try {
      return await _startAndWait(args);
    } finally {
      _launching = false;
    }
  }

  Future<CallToolResult> _startAndWait(Map<String, Object?> args) async {
    _lastProjectDir = args['projectDir'] as String;
    _lastDevice = args['device'] as String;
    final timeoutSec = (args['timeoutSec'] as num?)?.toInt() ?? 600;
    final command = await _launcher.start(
      projectDir: args['projectDir'] as String,
      device: args['device'] as String,
      target: args['target'] as String? ?? 'integration_test/mcp_test.dart',
      mode: args['mode'] as String? ?? 'run',
      port: (args['port'] as num?)?.toInt(),
      dartDefines: (args['dartDefines'] as List?)?.cast<String>() ?? const [],
      extraArgs: (args['extraArgs'] as List?)?.cast<String>() ?? const [],
      adbForward: args['adbForward'] == true,
    );
    final client = _launchedClient = _client = AppClient(
      'http://127.0.0.1:${_launcher.port}',
    );
    _carried = (passed: 0, failures: <String>[]);

    final clock = Stopwatch()..start();
    while (clock.elapsed < Duration(seconds: timeoutSec)) {
      if (await client.health()) {
        return _text({
          'ready': true,
          'command': command,
          'url': client.baseUrl,
        });
      }
      if (_launcher.exit case final exit?) {
        return _fail(
          'App process exited early (${jsonEncode(exit)}). Last logs:\n'
          '${_launcher.recentLogs(25).join('\n')}',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return _fail(
      'Timed out after ${timeoutSec}s. Last logs:\n'
      '${_launcher.recentLogs(25).join('\n')}',
    );
  }

  Future<CallToolResult> _stopApp({required bool ignoreErrors}) async {
    if (_stopping case final stopping?) {
      return stopping;
    }
    _stopping = _shutdownApp(_client, ignoreErrors: ignoreErrors);
    try {
      return await _stopping!;
    } finally {
      _stopping = null;
    }
  }

  Future<CallToolResult> _shutdownApp(
    AppClient client, {
    bool ignoreErrors = false,
  }) async {
    Object? expectations;
    try {
      final body = await client.call(CommandMethod.shutdown, {
        'ignoreErrors': ignoreErrors,
      }, _shutdownTimeout);
      expectations = _withCarried(body['result'] as Map<String, Object?>);
    } catch (_) {
      // The app may already have exited.
    }
    try {
      await _launcher.stop();
    } catch (error) {
      return _fail(error);
    }
    return _text({
      'stopped': true,
      if (expectations != null) 'expectations': expectations,
    });
  }

  Future<CallToolResult> _restart(Map<String, Object?> args) async {
    if (_stopping != null || _launching) {
      return _fail('The app is starting or stopping. Try app_restart again.');
    }
    final timeout = Duration(
      seconds: (args['timeoutSec'] as num?)?.toInt() ?? 60,
    );
    final client = _client;
    if (!_launcher.canHotRestart || !identical(client, _launchedClient)) {
      return _textWithAppErrors(
        await client.call(CommandMethod.restart, const {}, timeout),
      );
    }

    final results =
        (await client.call(CommandMethod.results))['result']
            as Map<String, Object?>;
    final before = await client.bootId();
    await _launcher.hotRestart();
    final clock = Stopwatch()..start();
    while (clock.elapsed < timeout) {
      final bootId = await client.bootId();
      if (bootId != null && bootId != before) {
        // Count them only once the old isolate is gone for sure.
        _carried = (
          passed: _carried.passed + (results['passed'] as int),
          failures: [
            ..._carried.failures,
            ...(results['failures'] as List).cast<String>(),
          ],
        );
        // Answers only once main() ran again and the command loop is up.
        await client.call(CommandMethod.status, const {}, timeout);
        return _text({'restarted': true, 'kind': 'hot'});
      }
      if (_launcher.exit case final exit?) {
        return _fail(
          'App process exited during hot restart (${jsonEncode(exit)}). '
          'Last logs:\n${_launcher.recentLogs(25).join('\n')}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return _fail(
      'Hot restart timed out after ${timeout.inSeconds}s. Last logs:\n'
      '${_launcher.recentLogs(25).join('\n')}',
    );
  }

  /// Adds [_carried] to expectation totals (and failures, when listed).
  Map<String, Object?> _withCarried(Map<String, Object?> counts) => {
    ...counts,
    'passed': (counts['passed'] as int? ?? 0) + _carried.passed,
    'failed': (counts['failed'] as int? ?? 0) + _carried.failures.length,
    if (counts['failures'] case final List failures)
      'failures': [..._carried.failures, ...failures],
  };

  Future<Map<String, Object?>> _screenshot(
    AppClient client,
    Map<String, Object?> params,
  ) async {
    final body = await client.call(CommandMethod.screenshot, params);
    return body['result'] as Map<String, Object?>;
  }

  Future<List<Content>> _captureShot(
    AppClient client,
    String path,
    bool withImage,
  ) async {
    try {
      final result = await _screenshot(client, {'maxWidth': _shotWidth});
      final data = result['pngBase64'] as String;
      await _saveScreenshot(path, data);
      return [
        if (withImage) ImageContent(data: data, mimeType: 'image/png'),
        TextContent(text: 'shot saved $path'),
      ];
    } catch (error) {
      return [TextContent(text: 'shot failed: $error')];
    }
  }

  Future<void> _saveScreenshot(String path, String data) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(base64Decode(data));
  }

  Future<CallToolResult> _enterEnv(Map<String, Object?> args) async {
    final client = _client;
    final name = args.remove('name') as String;
    final values = await _readEnv();
    final value = values[name];
    if (value == null) {
      final names = values.isEmpty ? 'none' : values.keys.join(', ');
      return _fail(
        'Variable "$name" is not defined in the env file (available names: $names).',
      );
    }
    final body = await client.call(CommandMethod.enterText, {
      ...args,
      'text': value,
    });
    final result = body['result'] as Map<String, Object?>;
    _recorder.record('enterEnv', {...args, 'name': name});
    return _text({
      'typed': name,
      'chars': value.runes.length,
      'settled': result['settled'],
    });
  }

  Future<Map<String, String>> _readEnv() async {
    final file = _envFile;
    if (file == null || file.isEmpty) {
      return {};
    }
    final pairs = <String, String>{};
    for (final raw in await File(file).readAsLines()) {
      final line = raw.trim();
      final equals = line.indexOf('=');
      if (line.startsWith('#') || equals < 1) {
        continue;
      }
      final key = line
          .substring(0, equals)
          .trim()
          .replaceFirst(RegExp(r'^export\s+'), '');
      var value = line.substring(equals + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.length < 2 ? '' : value.substring(1, value.length - 1);
      }
      pairs[key] = value;
    }
    return pairs;
  }
}

CallToolResult _text(Object? value) => CallToolResult(
  content: [TextContent(text: value is String ? value : _json.convert(value))],
);

/// The command's result, with `appErrors` alongside when the app reported any.
CallToolResult _textWithAppErrors(
  Map<String, Object?> body, {
  Map<String, Object?> Function(Map<String, Object?> result)? map,
}) {
  final raw = body['result'];
  final result = map != null && raw is Map<String, Object?> ? map(raw) : raw;
  return _text(
    body.containsKey('appErrors')
        ? {'result': result, 'appErrors': body['appErrors']}
        : result,
  );
}

CallToolResult _fail(Object error) => CallToolResult(
  isError: true,
  content: [TextContent(text: error is StateError ? error.message : '$error')],
);
