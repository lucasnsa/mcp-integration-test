const defaultCommandPort = 8765;

/// Method names used by the MCP server and the app's HTTP endpoint.
enum CommandMethod {
  status,
  snapshot,
  find,
  getText,
  screenshot,
  tap,
  longPress,
  doubleTap,
  tapAt,
  enterText,
  drag,
  fling,
  scrollUntilVisible,
  pressBack,
  sendKey,
  pump,
  pumpAndSettle,
  waitFor,
  expect,
  results,
  shutdown;

  static final byName = values.asNameMap();
}
