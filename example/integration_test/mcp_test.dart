import 'package:example_app/main.dart' as app;
import 'package:mcp_integration_test/mcp_integration_test.dart';

import 'mock_api.dart';
import 'mock_plugins.dart';

void main() => mcpIntegrationTest(() {
  final mocks = DemoPluginMocks()..install();
  app.runDemo(client: createDemoMockClient(), share: mocks.share);
});
