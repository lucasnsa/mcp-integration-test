# Changelog

## 0.2.0

- Add `recording_start`, `recording_stop` and `export_test` to turn recorded sessions into standalone Flutter integration tests. Exported `enterEnv` steps read values through `String.fromEnvironment` instead of embedding secrets.
- Add `app_restart`: use a hot restart for apps launched in run mode, or a soft restart in test mode and for connected apps; preserve expectation counters across restarts.
- Fix launching Flutter on Windows, where the Flutter command is a batch file.
- Require `mcp_integration_test_protocol` ^0.2.0.

## 0.1.0

- Provide a standalone Dart MCP server to launch and control Flutter integration tests.
