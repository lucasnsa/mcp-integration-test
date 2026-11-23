import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Injected only by test entry points; normal builds use a real HTTP client.
MockClient createDemoMockClient() => MockClient((request) async {
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (request.method != 'GET' ||
      request.url.host != 'jsonplaceholder.typicode.com' ||
      request.url.path != '/users') {
    return http.Response(
      '{"error":"Not found"}',
      404,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response(
    jsonEncode([
      {'name': 'Lucas', 'email': 'lucas@example.com'},
      {'name': 'Kaue', 'email': 'kaue@example.com'},
      {'name': 'Eduardo', 'email': 'eduardo@example.com'},
    ]),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});
