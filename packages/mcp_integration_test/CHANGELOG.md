# Changelog

## 0.2.0

- Add soft restart support: rebuild the widget tree and rerun the app entry point while preserving expectation counters.
- Expose a boot ID through `/health` so clients can detect hot restarts.
- Retry binding the local server while a previous isolate releases its port after a hot restart.
- Fix shutdown so the response, including expectation results, reaches the client before the server closes.
- Require `mcp_integration_test_protocol` ^0.2.0.

## 0.1.0

- Expose Flutter integration tests through a local JSON-RPC endpoint for MCP clients.
