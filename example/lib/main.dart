import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'demo_api.dart';
import 'pages/api_page.dart';
import 'pages/errors_page.dart';
import 'pages/items_page.dart';
import 'pages/profile_page.dart';
import 'pages/plugins_page.dart';

void main() => runDemo();

void runDemo({http.Client? client, SharePlus? share}) =>
    runApp(DemoApp(client: client, share: share));

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, this.client, this.share});

  final http.Client? client;
  final SharePlus? share;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final http.Client _client = widget.client ?? http.Client();
  late final DemoApi _api = DemoApi(_client);

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MCP playground',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    home: LoginPage(api: _api, share: widget.share),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api, this.share});

  final DemoApi api;
  final SharePlus? share;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    super.dispose();
  }

  void _submit() {
    final user = _user.text.trim();
    if (user.isEmpty) {
      setState(() => _error = 'Enter a username');
      return;
    }
    setState(() => _error = null);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            HomePage(user: user, api: widget.api, share: widget.share),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Login')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'MCP playground',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Sign in with any name to explore the demo screens.'),
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey('username'),
          controller: _user,
          decoration: InputDecoration(labelText: 'Username', errorText: _error),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('login'),
          onPressed: _submit,
          child: const Text('Sign in'),
        ),
        TextButton(
          key: const ValueKey('errors-demo'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ErrorsDemoPage()),
          ),
          child: const Text('Errors demo'),
        ),
      ],
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.user,
    required this.api,
    this.share,
  });

  final String user;
  final DemoApi api;
  final SharePlus? share;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Hello, $user')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Choose a screen to test'),
        _destination(
          context,
          'open-items',
          Icons.list,
          'Items',
          '100 rows, scrolling and item details',
          const ItemsPage(),
        ),
        _destination(
          context,
          'open-profile',
          Icons.person,
          'Profile form',
          'Validation, switches and saved state',
          const ProfilePage(),
        ),
        _destination(
          context,
          'open-api',
          Icons.cloud,
          'API demo',
          'HTTP loading, success, error and retry',
          ApiPage(api: api),
        ),
        _destination(
          context,
          'open-errors',
          Icons.bug_report,
          'Errors demo',
          'Trigger layout overflow and callback exceptions',
          const ErrorsDemoPage(),
        ),
        _destination(
          context,
          'open-share',
          Icons.share,
          'Share',
          'Share a message and inspect the result',
          SharePage(share: share),
        ),
        _destination(
          context,
          'open-package-info',
          Icons.info,
          'App information',
          'App name, package, version and build',
          const PackageInfoPage(),
        ),
        _destination(
          context,
          'open-permissions',
          Icons.camera_alt,
          'Camera permission',
          'Check access, request permission and open settings',
          const PermissionsPage(),
        ),
      ],
    ),
  );

  Widget _destination(
    BuildContext context,
    String key,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) => Card(
    child: ListTile(
      key: ValueKey(key),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page)),
    ),
  );
}
