import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A command received from the client, waiting to be executed by the session.
class PendingCommand {
  PendingCommand(this.method, this.params);

  final String method;
  final Map<String, Object?> params;
  final Completer<Map<String, Object?>> _completer = Completer();

  Future<Map<String, Object?>> get response => _completer.future;

  void complete(Map<String, Object?> response) {
    if (!_completer.isCompleted) _completer.complete(response);
  }
}

/// Loopback-only HTTP server.
///
/// * `GET  /health` -> `{"ok": true}`
/// * `POST /rpc`    -> body `{"method": "...", "params": {...}}`
///
/// Commands are queued and executed one at a time by the test body.
class CommandServer {
  CommandServer(this.port);

  final int port;
  HttpServer? _server;
  final StreamController<PendingCommand> _commands = StreamController();

  Stream<PendingCommand> get commands => _commands.stream;

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    await _commands.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      // The server drives the UI; refuse browser-originated requests so a web
      // page can't reach it through localhost (CSRF / DNS rebinding).
      if (request.headers.value('origin') != null) {
        return _send(response, HttpStatus.forbidden, {'ok': false, 'error': 'Origin not allowed'});
      }
      if (request.method == 'GET' && request.uri.path == '/health') {
        return _send(response, HttpStatus.ok, {'ok': true});
      }
      if (request.method != 'POST' || request.uri.path != '/rpc') {
        return _send(response, HttpStatus.notFound, {'ok': false, 'error': 'Not found'});
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        return _send(response, HttpStatus.unsupportedMediaType, {
          'ok': false,
          'error': 'Content-Type must be application/json',
        });
      }
      final Object? body = jsonDecode(await utf8.decoder.bind(request).join());
      if (body is! Map || body['method'] is! String) {
        return _send(response, HttpStatus.badRequest, {'ok': false, 'error': 'Expected {"method": string, "params": object}'});
      }
      final params = body['params'];
      final command = PendingCommand(
        body['method'] as String,
        params is Map ? params.cast<String, Object?>() : <String, Object?>{},
      );
      if (_commands.isClosed) {
        return _send(response, HttpStatus.gone, {'ok': false, 'error': 'Session finished'});
      }
      _commands.add(command);
      _send(response, HttpStatus.ok, await command.response);
    } catch (e) {
      try {
        _send(response, HttpStatus.internalServerError, {'ok': false, 'error': '$e'});
      } catch (_) {}
    }
  }

  void _send(HttpResponse response, int status, Map<String, Object?> body) {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    unawaited(response.close());
  }
}
