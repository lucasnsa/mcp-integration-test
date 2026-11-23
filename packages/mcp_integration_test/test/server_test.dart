import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_integration_test/src/server.dart';

/// A port that is free right now.
Future<int> _freePort() async {
  final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close(force: true);
  return port;
}

Future<Map<String, Object?>> _health(int port) async {
  final client = HttpClient();
  try {
    final request = await client.get('127.0.0.1', port, '/health');
    final response = await request.close();
    return (jsonDecode(await utf8.decoder.bind(response).join()) as Map).cast<String, Object?>();
  } finally {
    client.close(force: true);
  }
}

/// Starts a server with a listener on its commands, as the session does
/// (closing an unlistened single-subscription stream never completes).
Future<CommandServer> _start(int port) async {
  final server = CommandServer(port);
  server.commands.listen((_) {});
  await server.start();
  return server;
}

void main() {
  test('/health reports a bootId that differs per server instance', () async {
    final port = await _freePort();
    final first = await _start(port);
    final firstHealth = await _health(port);
    await first.close();

    final second = await _start(port);
    final secondHealth = await _health(port);
    await second.close();

    expect(firstHealth['ok'], isTrue);
    expect(firstHealth['bootId'], isA<String>().having((id) => id, 'bootId', isNotEmpty));
    expect(secondHealth['bootId'], isNot(firstHealth['bootId']));
  });

  test('close() right after completing a command still delivers its response', () async {
    final port = await _freePort();
    final server = CommandServer(port);
    // Like the session's shutdown: answer, then close the server at once.
    server.commands.listen((command) {
      command.complete({'ok': true, 'result': 'bye'});
      server.close();
    });
    await server.start();

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.post('127.0.0.1', port, '/rpc');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'method': 'shutdown', 'params': {}}));
    final response = await request.close();
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;

    expect(body['result'], 'bye');
  });

  test('start() retries until the port is released', () async {
    final port = await _freePort();
    final holder = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    Future<void>.delayed(const Duration(milliseconds: 300), () => holder.close(force: true));

    final server = await _start(port);
    final health = await _health(port);
    await server.close();

    expect(health['bootId'], server.bootId);
  });
}
