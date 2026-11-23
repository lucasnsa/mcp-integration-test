import 'dart:convert';

import 'package:http/http.dart' as http;

class DemoUser {
  const DemoUser({required this.name, required this.email});

  final String name;
  final String email;
}

class DemoApi {
  DemoApi(this.client);

  final http.Client client;

  Future<List<DemoUser>> fetchUsers({bool invalidEndpoint = false}) async {
    final response = await client
        .get(
          Uri.https(
            'jsonplaceholder.typicode.com',
            invalidEndpoint ? '/missing' : '/users',
          ),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw DemoApiException(response.statusCode);
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((entry) {
      final user = entry as Map<String, dynamic>;
      return DemoUser(
        name: user['name'] as String,
        email: user['email'] as String,
      );
    }).toList();
  }
}

class DemoApiException implements Exception {
  const DemoApiException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Could not load users (HTTP $statusCode)';
}
