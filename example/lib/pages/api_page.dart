import 'package:flutter/material.dart';

import '../demo_api.dart';

class ApiPage extends StatefulWidget {
  const ApiPage({super.key, required this.api});

  final DemoApi api;

  @override
  State<ApiPage> createState() => _ApiPageState();
}

class _ApiPageState extends State<ApiPage> {
  late Future<List<DemoUser>> _users;

  @override
  void initState() {
    super.initState();
    _users = widget.api.fetchUsers();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('API demo')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Browse users, request an unavailable page, and retry after an error.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('load-users'),
              onPressed: () => setState(() {
                _users = widget.api.fetchUsers();
              }),
              child: const Text('Load users / retry'),
            ),
            OutlinedButton(
              key: const ValueKey('api-error'),
              onPressed: () => setState(() {
                _users = widget.api.fetchUsers(invalidEndpoint: true);
              }),
              child: const Text('Request invalid endpoint'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FutureBuilder<List<DemoUser>>(
          future: _users,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(key: ValueKey('api-loading')),
              );
            }
            if (snapshot.hasError) {
              return Text(
                'Request failed: ${snapshot.error}',
                key: const ValueKey('api-failure'),
              );
            }
            final users = snapshot.data!;
            if (users.isEmpty) {
              return const Text('No users found', key: ValueKey('api-empty'));
            }
            return Column(
              key: const ValueKey('api-users'),
              children: users
                  .map(
                    (user) => ListTile(
                      title: Text(user.name),
                      subtitle: Text(user.email),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}
