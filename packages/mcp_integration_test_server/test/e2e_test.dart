@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:test/test.dart';

/// Drives the example app headless (`flutter test` on flutter-tester) through
/// the real MCP server over stdio, the same way an agent does.
///
/// Needs `flutter` on PATH. Run with `dart test -t e2e`.
void main() {
  late Process process;
  late ServerConnection server;
  final stderrLines = <String>[];

  /// Calls [tool] and returns its decoded JSON result; fails on a tool error.
  Future<Object?> call(
    String tool, [
    Map<String, Object?> args = const {},
  ]) async {
    final result = await server.callTool(
      CallToolRequest(name: tool, arguments: args),
    );
    final text = result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join('\n');
    if (result.isError == true) {
      fail('$tool failed: $text\nserver stderr:\n${stderrLines.join('\n')}');
    }
    return jsonDecode(text);
  }

  /// The tool's result without the `appErrors` wrapper.
  Object? resultOf(Object? response) =>
      response is Map && response.containsKey('appErrors')
      ? response['result']
      : response;

  setUpAll(() async {
    process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/mcp_integration_test_server.dart',
    ]);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderrLines.add);
    final client = MCPClient(Implementation(name: 'e2e', version: '0.0.0'));
    server = client.connectServer(
      stdioChannel(input: process.stdout, output: process.stdin),
    );
    await server.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    server.notifyInitialized();
  });

  tearDownAll(() async {
    await server.shutdown();
    process.kill();
    await process.exitCode;
  });

  test('a full session on the example app', () async {
    final exampleDir = Directory('../../example').absolute.path;
    final launch =
        await call('app_launch', {
              'projectDir': exampleDir,
              'device': 'flutter-tester',
              'mode': 'test',
              'timeoutSec': 600,
            })
            as Map;
    expect(launch['ready'], isTrue);

    final nodes = (await call('snapshot') as Map)['nodes'] as List;
    expect(
      nodes.map((n) => (n as Map)['key']),
      containsAll(['login', 'errors-demo']),
    );

    expect(await call('recording_start'), containsPair('recording', true));
    await call('enterText', {
      'finder': {'key': 'username'},
      'text': 'eduardo',
    });
    await call('tap', {
      'finder': {'key': 'login'},
    });
    expect(
      await call('expect', {
        'finder': {'text': 'Hello, eduardo'},
      }),
      containsPair('ok', true),
    );
    expect(
      await call('expect', {
        'finder': {'text': 'Login'},
      }),
      containsPair('ok', false),
      reason: 'the login screen is gone; this failure is on purpose',
    );

    expect(resultOf(await call('app_restart')), containsPair('kind', 'soft'));
    expect(
      resultOf(
        await call('getText', {
          'finder': {'key': 'username'},
        }),
      ),
      containsPair('texts', contains('')),
      reason: 'the restart clears the field',
    );
    expect(
      await call('test_results'),
      allOf(containsPair('passed', 1), containsPair('failed', 1)),
    );

    expect(
      await call('recording_stop'),
      containsPair('tools', [
        'enterText',
        'tap',
        'expect',
        'expect',
        'app_restart',
      ]),
      reason: 'queries (snapshot, getText, test_results) are not recorded',
    );

    await call('tap', {
      'finder': {'key': 'errors-demo'},
    });
    final thrown =
        await call('tap', {
              'finder': {'key': 'throw'},
            })
            as Map;
    expect(
      thrown['appErrors'],
      contains(containsPair('summary', contains('boom from onPressed'))),
      reason: 'an exception in a callback comes back with the command',
    );
    expect(
      (await call('app_errors', {'clear': true}) as Map)['errors'],
      isNotEmpty,
    );

    final stop = await call('app_stop') as Map;
    expect(stop['stopped'], isTrue);
    expect(
      stop['expectations'],
      allOf(containsPair('passed', 1), containsPair('failed', 1)),
    );

    // The recording becomes a plain integration test that passes without MCP.
    final export =
        await call('export_test', {
              'name': 'e2e_recorded_session',
              'imports': ['demo_app.dart'],
              'appMain': 'startDemoApp();',
              'overwrite': true,
            })
            as Map;
    final path = export['path'] as String;
    addTearDown(() => File(path).delete());
    expect(export, containsPair('skippedExpectations', 1));
    final source = await File(path).readAsString();
    expect(
      source,
      allOf(
        contains("find.byKey(const ValueKey<String>('username'))"),
        contains("expect(find.text('Hello, eduardo'), findsWidgets);"),
        contains('// Did not hold while recording'),
      ),
    );

    final replay = await Process.run(
      'flutter',
      [
        'test',
        'integration_test/e2e_recorded_session_test.dart',
        '-d',
        'flutter-tester',
      ],
      workingDirectory: exampleDir,
      runInShell: Platform.isWindows,
    );
    expect(
      replay.exitCode,
      0,
      reason: 'exported test failed:\n${replay.stdout}\n${replay.stderr}',
    );
  });
}
