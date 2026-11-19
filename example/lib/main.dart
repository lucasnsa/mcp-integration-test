import 'package:flutter/material.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Demo',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        home: const LoginPage(),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  String? _error;

  void _submit() {
    if (_user.text.trim().isEmpty) {
      setState(() => _error = 'Enter a username');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemsPage(user: _user.text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Login')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            TextField(
              key: const ValueKey('username'),
              controller: _user,
              decoration: InputDecoration(labelText: 'Username', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(key: const ValueKey('login'), onPressed: _submit, child: const Text('Sign in')),
            TextButton(
              key: const ValueKey('errors-demo'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ErrorsDemoPage())),
              child: const Text('Errors demo'),
            ),
          ]),
        ),
      );
}

class ItemsPage extends StatelessWidget {
  const ItemsPage({super.key, required this.user});
  final String user;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Hello, $user')),
        body: ListView.builder(
          itemCount: 100,
          itemBuilder: (_, i) => ListTile(title: Text('Item $i'), onTap: () {}),
        ),
      );
}

/// Triggers the kinds of errors the MCP session reports as `appErrors`.
class ErrorsDemoPage extends StatelessWidget {
  const ErrorsDemoPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Errors demo')),
        body: Column(children: [
          // RenderFlex overflow: wider than the screen.
          const Row(children: [Text('This row is intentionally far too wide to fit on a phone screen at all')]),
          FilledButton(
            key: const ValueKey('throw'),
            onPressed: () => throw StateError('boom from onPressed'),
            child: const Text('Throw in callback'),
          ),
        ]),
      );
}
