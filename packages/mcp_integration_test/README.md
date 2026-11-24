# mcp_integration_test

Drive a Flutter integration test through a local loopback JSON-RPC server.
An MCP client can inspect widgets, perform actions, capture screenshots, and
check assertions through the companion `mcp_integration_test_server` package.

## Setup

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
  mcp_integration_test: ^0.2.0
```

Create `integration_test/mcp_test.dart`, replacing `my_app` with your app package:

```dart
import 'package:my_app/main.dart' as app;
import 'package:mcp_integration_test/mcp_integration_test.dart';

void main() => mcpIntegrationTest(app.main);
```

Install the companion server:

```bash
dart pub global activate mcp_integration_test_server
```

Configure your MCP client to run `dart` with arguments
`pub global run mcp_integration_test_server`, then use `app_launch` with the
app's project directory and device. Flutter must be available on `PATH`.

Requires Flutter 3.35 or later and Dart 3.9 or later. Supports mobile and
desktop through `dart:io`; Flutter web is unsupported. The HTTP endpoint binds
to loopback. Keep the harness in a dedicated integration test entry point.

See the [project documentation](https://github.com/lucasnsa/mcp-integration-test)
for client configuration, environment variables, tools, and limitations.
