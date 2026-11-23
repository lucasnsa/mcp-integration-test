# MCP playground

A Flutter app for exercising the MCP integration test tools on mobile and desktop.

## Run

From this directory:

```bash
flutter pub get
flutter run -d <device> -t integration_test/mcp_test.dart
```

For Android, forward the endpoint before calling `app_connect`:

```bash
adb forward tcp:8765 tcp:8765
```

Alternatively, let `app_launch` build and connect automatically, with this
folder as `projectDir`, the device id, and `adbForward: true` for Android.
Running `flutter run -t lib/main.dart` starts the normal app without the MCP
harness and uses the real JSONPlaceholder API.

## Screens

| Screen | Scenarios | Finder keys |
| --- | --- | --- |
| Login | Empty-name validation, login, logout through back navigation | `username`, `login` |
| Home | Navigate to the demo screens | `open-items`, `open-profile`, `open-api`, `open-errors` |
| Items | Scroll through 100 rows and open details | `items-list`, `item-0` through `item-99` |
| Item details | Toggle favorite state | `favorite`, `favorite-status` |
| Profile form | Required name, valid email, notification switch, save | `profile-name`, `profile-email`, `notifications`, `save-profile`, `profile-result` |
| API demo | Loading, users, HTTP 404, retry | `api-loading`, `api-users`, `api-error`, `api-failure`, `load-users`, `api-empty` |
| Share | Message validation, success, dismissal, unavailable result | `open-share`, `share-text`, `share-send`, `share-result` |
| App information | Name, package identifier, version and build | `open-package-info`, `package-app-name`, `package-name`, `package-version`, `package-build` |
| Camera permission | Denied, granted, permanently denied and settings | `open-permissions`, `permission-status`, `permission-request`, `permission-check`, `permission-settings`, `settings-result` |
| Errors demo | Optional Row overflow and gesture exception | `toggle-overflow`, `overflow-row`, `throw` |

## HTTP mocks

`DemoApi` receives an `http.Client` rather than using top-level HTTP functions.
The MCP entry point injects `createDemoMockClient()` from
`integration_test/mock_api.dart`, using the `MockClient` supplied by
[`package:http/testing.dart`](https://pub.dev/documentation/http/latest/testing/).
No code generation or additional mock framework is required.

The mock returns three users for `GET /users`, waits 300 ms to exercise the
loading state, and returns HTTP 404 for the invalid endpoint button. Modify the
handler or inject another `MockClient` to test empty lists, malformed responses,
and other status codes. Normal app builds use a real HTTP client.

## Native plugin mocks

The app calls the real APIs of `share_plus`, `package_info_plus`, and
`permission_handler`. The normal `lib/main.dart` entry point uses their native
implementations. The MCP entry point installs the test implementations in
`integration_test/mock_plugins.dart` before starting the app:

- **Share:** `SharePlus.custom(DemoSharePlatform())` injects a `SharePlatform`
  implementation. It records `ShareParams` and cycles through `success`,
  `dismissed`, and `unavailable`; no share sheet opens and no message is sent.
- **App information:** `PackageInfo.setMockInitialValues` provides the fixture
  `MCP Playground`, `dev.example.mcp_playground`, version `2.3.4`, build `42`.
- **Camera permission:** a `PermissionHandlerPlatform` implementation initially
  reports `denied`. Requests cycle through `denied`, `granted`, and
  `permanentlyDenied`. Opening settings is recorded and returns `true` without
  leaving the app. This scripted sequence tests UI branches; it does not model
  every native permission transition or change the device's real permissions.

Edit the mock outcome lists to select other scenarios. Tests restore the
permission platform singleton after each case; package info fixtures live only
in the test isolate. The share mock is passed explicitly to avoid cached
singleton state between tests. Mocks and platform-interface dependencies stay
in test code/dev dependencies.

The example declares Android camera permission, with camera hardware optional.
Real permissions require platform support (`permission_handler` does not provide
Linux support). Native share sheets and OS permission dialogs are outside the
Flutter widget tree and cannot be inspected with this MCP's widget finders;
the mocks let the same app UI run deterministically. Native behavior still needs
separate device validation. The example's plugin versions retain compatibility
with the project's Flutter 3.35 baseline.

## Deliberate errors

Entering the Errors demo does not raise an error. Enable `toggle-overflow` to
create a Row that exceeds the available width by exactly 80 logical pixels,
even on desktop. Overflow reporting requires a debug build. Turn the switch off
to restore the layout. The `throw` button throws `StateError('boom from onPressed')`.

Use `app_errors` to inspect the captured errors. Fix the layout or leave the
screen, then acknowledge deliberate errors with `app_errors {clear: true}` so
they do not fail `app_stop`. API failures are handled in the UI and should not
appear in `app_errors`.

## Suggested MCP flow

1. Sign in, open Items, scroll to `Item 75`, open its details, and toggle Favorite.
2. Return Home, open Profile form, verify validation, fill it, toggle notifications, and save.
3. Open API demo, wait for `api-users`, request the invalid endpoint, verify `api-failure`, and retry.
4. Open Share, submit a message three times, and verify the success, dismissed, and unavailable results.
5. Open App information and verify version `2.3.4` and build `42`.
6. Open Camera permission, request access three times, verify the scripted statuses, and open settings.
7. Open Errors demo, enable overflow, inspect `app_errors`, disable overflow, trigger the callback exception, and acknowledge both errors.

Use `snapshot` after navigation and `expect` for assertions. For endurance tests,
repeat normal flows and inspect `test_results` and `app_errors` between cycles.

## Automated checks

```bash
flutter test test/
flutter analyze --no-fatal-infos
```
