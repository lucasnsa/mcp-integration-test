import 'package:example_app/main.dart' as app;

import 'mock_api.dart';
import 'mock_plugins.dart';

/// Starts the example app with its test doubles (HTTP API and plugins).
///
/// Shared by the MCP entry point (`mcp_test.dart`) and by tests exported from
/// a recorded session (`export_test` with `imports: ["demo_app.dart"]` and
/// `appMain: "startDemoApp();"`).
void startDemoApp() {
  final mocks = DemoPluginMocks()..install();
  app.runDemo(client: createDemoMockClient(), share: mocks.share);
}
