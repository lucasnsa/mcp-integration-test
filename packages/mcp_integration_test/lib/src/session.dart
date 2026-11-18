import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'executor.dart';
import 'server.dart';

/// Port the in-app server listens on. Override with
/// `--dart-define=MCP_IT_PORT=1234`.
const int _defaultPort = int.fromEnvironment('MCP_IT_PORT', defaultValue: 8765);

/// Entry point for an MCP-controlled integration test build.
///
/// Registers one long-lived `testWidgets` that launches [appMain] and then
/// executes commands sent over the local server until a `shutdown` command
/// arrives. Failed `expect` commands make the test (and therefore
/// `flutter test` / `flutter drive`) fail, like regular integration tests.
void mcpIntegrationTest(FutureOr<void> Function() appMain, {int port = _defaultPort}) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('MCP session', (tester) async {
    final server = CommandServer(port);
    await server.start();
    // ignore: avoid_print
    print('MCP_INTEGRATION_TEST_READY port=$port');

    final executor = CommandExecutor(tester, binding);
    await appMain();
    await tester.pump();

    await for (final command in server.commands) {
      if (command.method == 'shutdown') {
        command.complete({'ok': true, 'result': await executor.run('results', {})});
        break;
      }
      command.complete(await _execute(executor, tester, command));
    }
    await server.close();

    if (executor.failedExpectations.isNotEmpty) {
      fail('${executor.failedExpectations.length} expectation(s) failed:\n'
          '${executor.failedExpectations.join('\n')}');
    }
  }, timeout: Timeout.none);
}

Future<Map<String, Object?>> _execute(
  CommandExecutor executor,
  WidgetTester tester,
  PendingCommand command,
) async {
  try {
    final result = await executor.run(command.method, command.params);
    // Surface framework errors (overflow, assertion...) without killing the
    // session.
    final exceptions = <String>[];
    Object? e;
    while ((e = tester.takeException()) != null) {
      exceptions.add('$e');
    }
    return {
      'ok': true,
      'result': result,
      if (exceptions.isNotEmpty) 'appExceptions': exceptions,
    };
  } catch (e) {
    return {'ok': false, 'error': '$e'};
  }
}
