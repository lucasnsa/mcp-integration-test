import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mcp_integration_test/src/errors.dart';
import 'package:mcp_integration_test/src/executor.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restart rebuilds the app from scratch and keeps expectation counters', (tester) async {
    var launches = 0;
    void appMain() {
      launches++;
      runApp(const _App());
    }

    final executor = CommandExecutor(tester, binding, ErrorCollector(), appMain);
    appMain();
    await tester.pump();

    await executor.run('enterText', {
      'finder': {'key': 'name'},
      'text': 'leftover',
    });
    await executor.run('tap', {
      'finder': {'key': 'next'},
    });
    expect(find.text('Second'), findsOneWidget);
    await executor.run('expect', {
      'finder': {'text': 'never shown'},
    });

    final result = await executor.run('restart', {}) as Map<String, Object?>;

    expect(result['restarted'], isTrue);
    expect(result['kind'], 'soft');
    expect(launches, 2);
    expect(find.text('Second'), findsNothing);
    expect(find.text('First'), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
    final results = await executor.run('results', {}) as Map<String, Object?>;
    expect(results['failed'], 1);
  });
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => const MaterialApp(home: _FirstPage());
}

class _FirstPage extends StatefulWidget {
  const _FirstPage();

  @override
  State<_FirstPage> createState() => _FirstPageState();
}

class _FirstPageState extends State<_FirstPage> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('First')),
        body: Column(children: [
          TextField(key: const ValueKey('name'), controller: _name),
          FilledButton(
            key: const ValueKey('next'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Second'))),
            ),
            child: const Text('Next'),
          ),
        ]),
      );
}
