import 'package:flutter/material.dart';

/// Deliberate failures, isolated from the normal demo screens.
class ErrorsDemoPage extends StatefulWidget {
  const ErrorsDemoPage({super.key});

  @override
  State<ErrorsDemoPage> createState() => _ErrorsDemoPageState();
}

class _ErrorsDemoPageState extends State<ErrorsDemoPage> {
  bool _overflow = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Errors demo')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'These controls deliberately cause Flutter errors. Use app_errors to inspect them and clear: true to acknowledge them.',
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const ValueKey('toggle-overflow'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Layout overflow'),
          subtitle: const Text(
            'Enable to overflow a Row by 80 logical pixels.',
          ),
          value: _overflow,
          onChanged: (value) => setState(() => _overflow = value),
        ),
        if (_overflow)
          LayoutBuilder(
            builder: (context, constraints) => Row(
              key: const ValueKey('overflow-row'),
              children: [
                Container(
                  width: constraints.maxWidth + 80,
                  height: 64,
                  color: Colors.amber,
                  alignment: Alignment.centerLeft,
                  child: const Text('Intentional RenderFlex overflow'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('throw'),
          onPressed: () => throw StateError('boom from onPressed'),
          child: const Text('Throw in callback'),
        ),
      ],
    ),
  );
}
