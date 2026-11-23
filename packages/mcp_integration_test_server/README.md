# mcp_integration_test_server

A standalone Dart MCP server that launches and controls a Flutter app using
the `mcp_integration_test` harness. Communicates with MCP clients over STDIO
and with the app over loopback HTTP.

## Install

Requires Dart 3.9 or later. Flutter 3.35 or later must be on `PATH` to launch
apps; Android devices also require `adb`.

```bash
dart pub global activate mcp_integration_test_server
```

Configure your MCP client with:

```json
{
  "mcpServers": {
    "flutter-it": {
      "command": "dart",
      "args": ["pub", "global", "run", "mcp_integration_test_server"]
    }
  }
}
```

Prepare the target app with the `mcp_integration_test` package, then call
`app_launch` with its project directory and device. Set the client's tool
timeout above the default 600-second launch timeout (for example, 660 seconds).

Tools cover app lifecycle, widget inspection, gestures, text input,
screenshots, assertions, and collected app errors. This server depends only
on Dart packages; Flutter is invoked as an external process.

See the [project documentation](https://github.com/lucasnsa/mcp-integration-test)
for app setup, environment variables, tool details, and limitations.
