# mcp-integration-test

A variant of Flutter's [`integration_test`](https://docs.flutter.dev/testing/integration-tests)
that you drive through a **local MCP server**. The app is built from a dedicated
entry point (`integration_test/mcp_test.dart`); inside it, a single long-lived
`testWidgets` runs on the real `IntegrationTestWidgetsFlutterBinding` and executes
commands (tap, enterText, scroll, expect, screenshot…) sent by the MCP server.

```
MCP client (Claude)  --stdio-->  mcp_integration_test_server  --HTTP 127.0.0.1:8765-->  app (mcp_integration_test)
                                       |                                                     WidgetTester + finders
                                       +-- starts the app with `flutter run` or `flutter test`
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

The server is a separate package (`packages/mcp_integration_test_server`), so
its dependencies (`dart_mcp`…) never enter your app's dependency graph. Install
it once with the Dart from your Flutter SDK, then register it:

```bash
dart pub global activate --source path /path/to/mcp-integration-test/packages/mcp_integration_test_server
claude mcp add flutter-it -- dart pub global run mcp_integration_test_server
```

Server environment variables (pass with `claude mcp add -e KEY=VALUE …`):

| Variable | Default | Purpose |
|---|---|---|
| `MCP_IT_PORT` | `8765` | Port of the in-app server |
| `MCP_IT_URL` | `http://127.0.0.1:$MCP_IT_PORT` | Initial app URL (before `app_launch` / `app_connect`) |
| `MCP_IT_ENV_FILE` | none | `KEY=VALUE` file read by `enterEnv` / `envKeys` (secrets stay out of the chat) |
| `MCP_IT_SHOT_WIDTH` | `360` | Max width of the `shot` screenshots taken after actions |

A path activation runs from the source, so code changes apply on the next
start; run the `activate` command again after changing the server's
`pubspec.yaml`.

To use this repository's `.mcp.json` instead, run `flutter pub get` in
`packages/mcp_integration_test_server`, then open Claude Code at the repository
root.

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
| Act | `tap`, `longPress`, `doubleTap`, `tapAt`, `enterText`, `enterEnv`, `drag`, `fling`, `scrollUntilVisible`, `pressBack`, `sendKey` |
| Test data | `envKeys` |
| Timing | `pump`, `pumpAndSettle`, `waitFor` |
| Assert | `expect`, `test_results` |

Finders: `{text | textContaining | key | type | tooltip | semanticsLabel, index, within, includeOffstage}`.
Actions pump and wait for animations by default (never fails on endless animations).

`expect` failures don't end the session; `app_stop` ends the test, so with
`mode: "test"` the process exits non-zero, like a normal integration test.

## Notes / limits

- Requires Flutter **>= 3.35.0** (Dart 3.9).
- Needs `dart:io`: mobile and desktop, **not Flutter web**.
- The in-app server binds to loopback only and rejects requests with an `Origin` header or a non-JSON content type.
- Screenshots use the render layer (debug/profile builds), so they work on every platform without the native plugin.
- Unexpected framework exceptions are returned as `appExceptions` instead of killing the session.
