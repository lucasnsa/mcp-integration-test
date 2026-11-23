import 'dart:convert';
import 'dart:io';

import 'package:mcp_integration_test_protocol/mcp_integration_test_protocol.dart';
import 'package:mcp_integration_test_server/src/app_client.dart';
import 'package:test/test.dart';

/// A stand-in for the in-app server: answers `/health` and `/rpc` with
/// [reply], and records the RPC bodies it receives.
class _FakeApp {
  late final HttpServer _server;
  final requests = <Map<String, Object?>>[];
  Map<String, Object?> Function(Map<String, Object?> body) reply = (_) => {
    'ok': true,
    'result': {},
  };
  Map<String, Object?> health = {'ok': true, 'bootId': 'boot-1'};

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final Map<String, Object?> body;
      if (request.uri.path == '/health') {
        body = health;
      } else {
        final rpc =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, Object?>;
        requests.add(rpc);
        body = reply(rpc);
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
  }

  Future<void> close() => _server.close(force: true);
}

/// A loopback URL where nothing is listening.
Future<String> _deadUrl() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return 'http://127.0.0.1:$port';
}

void main() {
  late _FakeApp app;
  late AppClient client;

  setUp(() async {
    app = _FakeApp();
    await app.start();
    client = AppClient(app.url);
  });
  tearDown(() => app.close());

  test('health and bootId reflect the app', () async {
    expect(await client.health(), isTrue);
    expect(await client.bootId(), 'boot-1');
  });

  test('call sends the method name and params and returns the body', () async {
    app.reply = (body) => {
      'ok': true,
      'result': {'echo': body['params']},
    };

    final body = await client.call(CommandMethod.tap, {
      'finder': {'key': 'login'},
    });

    expect(app.requests.single['method'], 'tap');
    expect(body['result'], {
      'echo': {
        'finder': {'key': 'login'},
      },
    });
  });

  test('an app error is raised with its message', () async {
    app.reply = (_) => {'ok': false, 'error': 'No widget found for key'};

    await expectLater(
      client.call(CommandMethod.tap),
      throwsA(
        isA<AppClientException>().having(
          (e) => e.message,
          'message',
          'No widget found for key',
        ),
      ),
    );
  });

  test('an unreachable app is reported, not thrown, by health', () async {
    final dead = AppClient(await _deadUrl());

    expect(await dead.health(), isFalse);
    expect(await dead.bootId(), isNull);
    await expectLater(
      dead.call(CommandMethod.status),
      throwsA(
        isA<AppClientException>().having(
          (e) => e.message,
          'message',
          contains('Cannot reach the app'),
        ),
      ),
    );
  });
}
