import 'dart:async';
import 'dart:io';

import 'package:mcp_integration_test_server/src/mcp_server.dart';

Future<void> main() async {
  final server = IntegrationTestMcpServer();
  final interrupted = Completer<void>();
  final signals = [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];
  final subscriptions = [
    for (final signal in signals)
      signal.watch().listen((_) {
        if (!interrupted.isCompleted) {
          interrupted.complete();
        }
      }),
  ];
  try {
    await Future.any([server.done, interrupted.future]);
    await server.closeApp();
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
  if (interrupted.isCompleted) {
    exit(0);
  }
}
