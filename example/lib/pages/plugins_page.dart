import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class SharePage extends StatefulWidget {
  const SharePage({super.key, this.share});

  final SharePlus? share;

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final _text = TextEditingController(text: 'Hello from the MCP playground');
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _share(BuildContext buttonContext) async {
    if (_text.text.trim().isEmpty) {
      setState(() => _result = 'Enter a message to share');
      return;
    }
    final box = buttonContext.findRenderObject()! as RenderBox;
    setState(() => _busy = true);
    try {
      final result = await (widget.share ?? SharePlus.instance).share(
        ShareParams(
          text: _text.text.trim(),
          subject: 'MCP playground',
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (!mounted) return;
      setState(
        () => _result = switch (result.status) {
          ShareResultStatus.success => 'Share action selected',
          ShareResultStatus.dismissed => 'Sharing dismissed',
          ShareResultStatus.unavailable => 'Share result unavailable',
        },
      );
    } catch (error) {
      if (mounted) setState(() => _result = 'Could not share: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Share')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Write a message and choose how to share it.'),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('share-text'),
          controller: _text,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('share-send'),
            onPressed: _busy ? null : () => _share(context),
            child: Text(_busy ? 'Sharing…' : 'Share message'),
          ),
        ),
        if (_result != null)
          Text(_result!, key: const ValueKey('share-result')),
      ],
    ),
  );
}

class PackageInfoPage extends StatefulWidget {
  const PackageInfoPage({super.key});

  @override
  State<PackageInfoPage> createState() => _PackageInfoPageState();
}

class _PackageInfoPageState extends State<PackageInfoPage> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App information')),
    body: FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load app information: ${snapshot.error}',
              key: const ValueKey('package-error'),
            ),
          );
        }
        final info = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ListTile(
              title: const Text('App name'),
              subtitle: Text(
                info.appName,
                key: const ValueKey('package-app-name'),
              ),
            ),
            ListTile(
              title: const Text('Package'),
              subtitle: Text(
                info.packageName,
                key: const ValueKey('package-name'),
              ),
            ),
            ListTile(
              title: const Text('Version'),
              subtitle: Text(
                info.version,
                key: const ValueKey('package-version'),
              ),
            ),
            ListTile(
              title: const Text('Build'),
              subtitle: Text(
                info.buildNumber,
                key: const ValueKey('package-build'),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  PermissionStatus? _status;
  bool _busy = true;
  String? _error;
  String? _settingsResult;

  @override
  void initState() {
    super.initState();
    _update(() => Permission.camera.status);
  }

  Future<void> _update(Future<PermissionStatus> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
      _settingsResult = null;
    });
    try {
      final status = await operation();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = 'Permission unavailable: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    setState(() => _busy = true);
    try {
      final opened = await openAppSettings();
      if (mounted) {
        setState(
          () => _settingsResult = opened
              ? 'Settings opened'
              : 'Could not open settings',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _settingsResult = 'Could not open settings: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Camera permission')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Check or request camera access. This demo does not capture photos.',
        ),
        const SizedBox(height: 16),
        Text(
          _busy ? 'Checking…' : 'Camera: ${_status?.name ?? 'unavailable'}',
          key: const ValueKey('permission-status'),
        ),
        if (_error != null)
          Text(_error!, key: const ValueKey('permission-error')),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('permission-request'),
          onPressed: _busy
              ? null
              : () => _update(() => Permission.camera.request()),
          child: const Text('Request camera access'),
        ),
        OutlinedButton(
          key: const ValueKey('permission-check'),
          onPressed: _busy
              ? null
              : () => _update(() => Permission.camera.status),
          child: const Text('Check current status'),
        ),
        if (_status == PermissionStatus.permanentlyDenied) ...[
          const Text(
            'Camera access is blocked. Enable it in app settings, then check the status again.',
          ),
          TextButton(
            key: const ValueKey('permission-settings'),
            onPressed: _busy ? null : _openSettings,
            child: const Text('Open app settings'),
          ),
        ],
        if (_settingsResult != null)
          Text(_settingsResult!, key: const ValueKey('settings-result')),
      ],
    ),
  );
}
