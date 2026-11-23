# mcp_integration_test_protocol

Shared command names and the default loopback port for
`mcp_integration_test` and `mcp_integration_test_server`.
This package uses pure Dart and has no Flutter dependencies.

```dart
import 'package:mcp_integration_test_protocol/mcp_integration_test_protocol.dart';

void main() {
  print(defaultCommandPort); // 8765
  print(CommandMethod.tap.name); // tap
}
```

Requires Dart 3.9 or later. See the
[project documentation](https://github.com/lucasnsa/mcp-integration-test)
for setup and usage.
