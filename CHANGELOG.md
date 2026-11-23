# Changelog

## Unreleased
* Feat: Record a session with `recording_start` / `recording_stop` and write it as a plain `integration_test` file with `export_test`, so agent-driven sessions become regression tests that run with `flutter test` in CI ([#5](https://github.com/lucasnsa/mcp-integration-test/issues/5)) by [@vilar95](https://github.com/vilar95)
* Feat: New `app_restart` tool resets the app to its initial screen; hot restart with `mode: "run"`, soft restart with `mode: "test"` or `app_connect`, expectation counters preserved ([#3](https://github.com/lucasnsa/mcp-integration-test/issues/3), [c399b70](https://github.com/lucasnsa/mcp-integration-test/commit/c399b70)) by [@vilar95](https://github.com/vilar95)
* Fix: `app_launch` starts Flutter on Windows, where `flutter` is a batch file ([dfd4959](https://github.com/lucasnsa/mcp-integration-test/commit/dfd4959)) by [@vilar95](https://github.com/vilar95)
* Fix: `app_stop` returns the expectation results; the in-app server closed the connection before the `shutdown` reply ([1be9d19](https://github.com/lucasnsa/mcp-integration-test/commit/1be9d19)) by [@vilar95](https://github.com/vilar95)
* Chore: Ignore FVM files and refresh the example lockfile ([d183c6b](https://github.com/lucasnsa/mcp-integration-test/commit/d183c6b)) by [@vilar95](https://github.com/vilar95)
* Test: `FinderSpec`, snapshot and `AppClient` tests, and an end-to-end session that drives the example app through the real MCP server ([#4](https://github.com/lucasnsa/mcp-integration-test/issues/4), [732f43a](https://github.com/lucasnsa/mcp-integration-test/commit/732f43a), [d2b261f](https://github.com/lucasnsa/mcp-integration-test/commit/d2b261f)) by [@vilar95](https://github.com/vilar95)
* Chore: CI on GitHub Actions, Linux with Flutter 3.35.0 and stable plus Windows ([#4](https://github.com/lucasnsa/mcp-integration-test/issues/4), [5a65272](https://github.com/lucasnsa/mcp-integration-test/commit/5a65272)) by [@vilar95](https://github.com/vilar95)

## 2026-11-19
* Feat: The MCP server is now a Dart package (`packages/mcp_integration_test_server`) built on `dart_mcp`, replacing the Node server ([#20](https://github.com/lucasnsa/mcp-integration-test/pull/20), [#1](https://github.com/lucasnsa/mcp-integration-test/issues/1)) by [@kmartins](https://github.com/kmartins)
* Fix: `app_launch` picks a free port when none is given, and `app_stop` removes the ADB forward ([#19](https://github.com/lucasnsa/mcp-integration-test/pull/19), [#2](https://github.com/lucasnsa/mcp-integration-test/issues/2)) by [@lucasnsa](https://github.com/lucasnsa)
* Feat: App errors (overflow, exceptions) are captured with stack, listed by the new `app_errors` tool, and fail the run on `app_stop` ([#18](https://github.com/lucasnsa/mcp-integration-test/pull/18), [#17](https://github.com/lucasnsa/mcp-integration-test/issues/17)) by [@lucasnsa](https://github.com/lucasnsa)

## 2026-11-18
* Feat: Evidence screenshots with `shot` on actions and `path` on `screenshot`; `enterEnv` / `envKeys` type secrets from an env file ([ffdb15c](https://github.com/lucasnsa/mcp-integration-test/commit/ffdb15c)) by [@lucasnsa](https://github.com/lucasnsa)
* Fix: Screenshots are no longer zoomed and cropped, and password fields are masked ([ffdb15c](https://github.com/lucasnsa/mcp-integration-test/commit/ffdb15c)) by [@lucasnsa](https://github.com/lucasnsa)
* Feat: First version: `mcp_integration_test` package, Node MCP server, lifecycle/inspect/action/assert tools and example app ([afe2cc1](https://github.com/lucasnsa/mcp-integration-test/commit/afe2cc1)) by [@lucasnsa](https://github.com/lucasnsa)
