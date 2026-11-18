/// Drive a Flutter app through the `integration_test` binding from a local
/// MCP server.
///
/// ```dart
/// // integration_test/mcp_test.dart
/// import 'package:my_app/main.dart' as app;
/// import 'package:mcp_integration_test/mcp_integration_test.dart';
///
/// void main() => mcpIntegrationTest(app.main);
/// ```
library;

export 'src/session.dart' show mcpIntegrationTest;
