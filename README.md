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

Install the server dependencies first:

```bash
cd mcp_server && npm install
```

### Claude Code

```bash
claude mcp add flutter-it -- node /path/to/mcp-integration-test/mcp_server/src/index.js
```

### Codex

Register the local STDIO server with the Codex CLI, using the absolute path to
your checkout:

```bash
codex mcp add flutter-it -- node /path/to/mcp-integration-test/mcp_server/src/index.js
codex mcp list
```

Codex stores the entry in `~/.codex/config.toml`. Set `tool_timeout_sec` to
`660` in that entry so `app_launch` can wait for its default 600-second build
timeout. Alternatively, add the complete entry directly:

```toml
[mcp_servers.flutter-it]
command = "node"
args = ["/path/to/mcp-integration-test/mcp_server/src/index.js"]
tool_timeout_sec = 660
```

You can also use a project-scoped `.codex/config.toml` in a trusted project.
In the desktop app, open **Settings → MCP servers → Add server**, choose
**STDIO**, and enter the same command and argument. Save and select **Restart**;
in the IDE extension, select **Restart extension**. Use `/mcp` in the desktop
app or Codex CLI to check connected servers.

Ensure `node`, `flutter`, and (for Android) `adb` are available on the MCP
server's `PATH`. See the [official MCP configuration documentation](https://learn.chatgpt.com/docs/extend/mcp).

## 3. Use it

Ask the agent to `app_launch` (projectDir + device), or start the build yourself:

```bash
flutter run -d <device> -t integration_test/mcp_test.dart      # or:
flutter test integration_test/mcp_test.dart -d <device>        # official flow
# Android/emulator: adb forward tcp:8765 tcp:8765   (app_launch does it with adbForward: true)
```
then `app_connect`. Port: `--dart-define=MCP_IT_PORT=1234` (+ `MCP_IT_PORT` env for the server).

`app_launch` automatically selects a free local port when `port` is omitted and
returns its URL. Pass `port` to request a specific port; an occupied port fails
before launching Flutter. With `adbForward: true`, `app_stop` removes the ADB
forward created by that launcher, including when the Flutter process has already
exited. Separate MCP server sessions can launch apps concurrently on different
ports. Manually started apps and `app_connect` still default to port 8765 (or
`MCP_IT_PORT`).

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
