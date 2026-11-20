import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_integration_test/command_protocol.dart';

/// Talks to the HTTP server embedded in the running test.
class AppClient {
  AppClient(this.baseUrl);

  final String baseUrl;

  Future<bool> health() async {
    try {
      final (status, _) = await _request(
        'GET',
        '/health',
        const Duration(milliseconds: 1500),
      );
      return status >= 200 && status < 300;
    } catch (_) {
      return false;
    }
  }

  /// Id of the app's current boot; changes after a hot restart. Null when the
  /// app does not answer.
  Future<String?> bootId() async {
    try {
      final (_, payload) = await _request(
        'GET',
        '/health',
        const Duration(milliseconds: 1500),
      );
      return (jsonDecode(payload) as Map<String, Object?>)['bootId'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> call(
    CommandMethod method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(minutes: 1),
  ]) async {
    final (status, payload) = await _request(
      'POST',
      '/rpc',
      timeout,
      body: {'method': method.name, 'params': params},
    );
    final body = jsonDecode(payload) as Map<String, Object?>;
    if (body['ok'] != true) {
      throw AppClientException(body['error'] as String? ?? 'HTTP $status');
    }
    return body;
  }

  Future<(int, String)> _request(
    String method,
    String path,
    Duration timeout, {
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient();
    try {
      return await (() async {
        final request = await client.openUrl(
          method,
          Uri.parse('$baseUrl$path'),
        );
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        return (response.statusCode, await utf8.decoder.bind(response).join());
      })().timeout(timeout);
    } on Exception catch (error) {
      throw AppClientException(
        'Cannot reach the app at $baseUrl ($error). '
        'Is the MCP test build running? Use app_launch, or start it manually '
        'and call app_connect.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class AppClientException implements Exception {
  AppClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
