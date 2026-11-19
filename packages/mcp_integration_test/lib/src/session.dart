import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'command_protocol.dart';
import 'errors.dart';
import 'executor.dart';
import 'server.dart';

/// Port the in-app server listens on. Override with
/// `--dart-define=MCP_IT_PORT=1234`.
const int _defaultPort = int.fromEnvironment('MCP_IT_PORT', defaultValue: defaultCommandPort);

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

    final errors = ErrorCollector()..install();
    final executor = CommandExecutor(tester, binding, errors);
    var ignoreErrors = false;
    await appMain();
    await tester.pump();

    await for (final command in server.commands) {
      if (command.method == CommandMethod.shutdown.name) {
        ignoreErrors = command.params['ignoreErrors'] == true;
        command.complete({'ok': true, 'result': await executor.run(CommandMethod.results.name, {})});
        break;
      }
      errors.currentCommand = command.method;
      command.complete(await _execute(executor, tester, errors, command));
      errors.currentCommand = '(between commands)';
    }
    await server.close();
    errors.uninstall();

    final problems = <String>[
      ...executor.failedExpectations,
      if (!ignoreErrors) ...errors.all.map((e) => 'app ${e.kind}: ${e.summary} (x${e.count})'),
    ];
    if (problems.isNotEmpty) {
      fail('${problems.length} problem(s):\n${problems.join('\n')}');
    }
  }, timeout: Timeout.none);
}

Future<Map<String, Object?>> _execute(
  CommandExecutor executor,
  WidgetTester tester,
  ErrorCollector errors,
  PendingCommand command,
) async {
  try {
    final result = await executor.run(command.method, command.params);
    // Drain the binding's pending exception so it does not fail the test on
    // its own; the collector already recorded it with its stack.
    while (tester.takeException() != null) {}
    final fresh = errors.takeNew();
    return {
      'ok': true,
      'result': result,
      if (fresh.isNotEmpty) 'appErrors': fresh,
    };
  } catch (e) {
    return {'ok': false, 'error': '$e'};
  }
}
