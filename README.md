# mcp-integration-test

A variant of Flutter's [`integration_test`](https://docs.flutter.dev/testing/integration-tests)
that you drive through a **local MCP server**. The app is built from a dedicated
entry point (`integration_test/mcp_test.dart`); inside it, a single long-lived
`testWidgets` runs on the real `IntegrationTestWidgetsFlutterBinding` and executes
commands (tap, enterText, scroll, expect, screenshot…) sent by the MCP server.

```
MCP client (Claude)  --stdio-->  mcp_server (Node)  --HTTP 127.0.0.1:8765-->  app (mcp_integration_test)
                                       |                                          WidgetTester + finders
                                       +-- spawns `flutter run|test -t integration_test/mcp_test.dart`
```

## 1. Add to your app

```yaml
# pubspec.yaml
dev_dependencies:
  integration_test: { sdk: flutter }
  mcp_integration_test: { path: /path/to/mcp-integration-test/packages/mcp_integration_test }
```

```dart
// integration_test/mcp_test.dart
import 'package:my_app/main.dart' as app;
import 'package:mcp_integration_test/mcp_integration_test.dart';

void main() => mcpIntegrationTest(app.main);
```

Production builds (`lib/main.dart`) never include it.

## 2. Register the MCP server

```bash
cd mcp_server && npm install
claude mcp add flutter-it -- node /path/to/mcp-integration-test/mcp_server/src/index.js
```

## 3. Use it

Ask the agent to `app_launch` (projectDir + device), or start the build yourself:

```bash
flutter run -d <device> -t integration_test/mcp_test.dart      # or:
flutter test integration_test/mcp_test.dart -d <device>        # official flow
# Android/emulator: adb forward tcp:8765 tcp:8765   (app_launch does it with adbForward: true)
```
then `app_connect`. Port: `--dart-define=MCP_IT_PORT=1234` (+ `MCP_IT_PORT` env for the server).

### Tools

| Group | Tools |
|---|---|
| Lifecycle | `app_launch`, `app_connect`, `app_logs`, `app_stop` |
| Inspect | `app_status`, `snapshot`, `find`, `getText`, `screenshot` |
| Act | `tap`, `longPress`, `doubleTap`, `tapAt`, `enterText`, `drag`, `fling`, `scrollUntilVisible`, `pressBack`, `sendKey` |
| Timing | `pump`, `pumpAndSettle`, `waitFor` |
| Assert | `expect`, `test_results`, `app_errors` |

Finders: `{text | textContaining | key | type | tooltip | semanticsLabel, index, within, includeOffstage}`.
Actions pump and wait for animations by default (never fails on endless animations).

`expect` failures don't end the session; `app_stop` ends the test, so with
`mode: "test"` the process exits non-zero, like a normal integration test.

## Notes / limits

- Requires Flutter **>= 3.35.0** (Dart 3.9). Verified on 3.35.0 and 3.47.7 (headless).
- Needs `dart:io`: mobile and desktop, **not Flutter web**.
- Server binds to loopback only and rejects requests with an `Origin` header or a non-JSON content type.
- Screenshots use the render layer (debug/profile builds), so they work on every platform without the native plugin.
- App errors (RenderFlex overflow, build/layout/paint exceptions, errors thrown in gesture callbacks) are collected with
  kind, count, triggering command and stack, and returned as `appErrors` in the response of the command that caused them
  (also via `app_errors`). They don't kill the session, but they **fail the test at `app_stop`** unless acknowledged with
  `app_errors {clear: true}` or `app_stop {ignoreErrors: true}`, like the official `integration_test`.
  Overflow is only reported by debug builds. Errors thrown from async code outside the framework's error zone are not captured yet.
- Verified here only headless (`flutter test` under `flutter_tester`); this machine has no `cmake`, so Linux desktop/Android were not run.
