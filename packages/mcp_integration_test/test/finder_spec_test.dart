import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_integration_test/src/finder_spec.dart';

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(children: [
            const Text('Login', key: ValueKey('title')),
            const Text('Welcome back'),
            const Tooltip(message: 'Help', child: Icon(Icons.help)),
            Semantics(label: 'Avatar', child: const SizedBox(width: 10, height: 10)),
            TextField(controller: TextEditingController(text: 'eduardo')),
            TextField(obscureText: true, controller: TextEditingController(text: 'secret')),
            Container(
              key: const ValueKey('form'),
              child: const Column(children: [Text('Item'), Text('Item')]),
            ),
            const Text('Item'),
            const Offstage(child: Text('Hidden')),
          ]),
        ),
      ),
    );

int _count(Object? json) => FinderSpec.fromJson(json).finder.evaluate().length;

void main() {
  testWidgets('each criterion matches its widget', (tester) async {
    await _pump(tester);

    expect(_count({'text': 'Login'}), 1);
    expect(_count({'textContaining': 'come ba'}), 1);
    expect(_count({'key': 'title'}), 1);
    expect(_count({'type': 'TextField'}), 2);
    expect(_count({'tooltip': 'Help'}), 1);
    expect(_count({'semanticsLabel': 'Avatar'}), 1);
    expect(_count({'text': 'eduardo'}), 1, reason: 'text fields match their content');
  });

  testWidgets('criteria are combined with AND', (tester) async {
    await _pump(tester);

    expect(_count({'text': 'Login', 'key': 'title'}), 1);
    expect(_count({'text': 'Welcome back', 'key': 'title'}), 0);
  });

  testWidgets('within limits matches to descendants of another finder', (tester) async {
    await _pump(tester);

    expect(_count({'text': 'Item'}), 3);
    expect(
      _count({
        'text': 'Item',
        'within': {'key': 'form'},
      }),
      2,
    );
  });

  testWidgets('index picks the target and is part of the description', (tester) async {
    await _pump(tester);

    final spec = FinderSpec.fromJson({'text': 'Item', 'index': 2});
    expect(spec.index, 2);
    expect(spec.target.evaluate().single.widget, isA<Text>());
    expect(spec.description, 'text == "Item" (index 2)');
  });

  testWidgets('offstage widgets match only with includeOffstage', (tester) async {
    await _pump(tester);

    expect(_count({'text': 'Hidden'}), 0);
    expect(_count({'text': 'Hidden', 'includeOffstage': true}), 1);
  });

  testWidgets('obscured fields match only their mask', (tester) async {
    await _pump(tester);

    expect(_count({'text': 'secret'}), 0);
    expect(_count({'textContaining': 'sec'}), 0);
    expect(_count({'text': '••••••'}), 1);
  });

  test('invalid finders are rejected with a helpful message', () {
    expect(() => FinderSpec.fromJson('Login'), throwsA(isA<ArgumentError>()));
    expect(
      () => FinderSpec.fromJson({'label': 'Login'}),
      throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', contains('Unknown finder field'))),
    );
    expect(
      () => FinderSpec.fromJson({'index': 1}),
      throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', contains('at least one'))),
    );
  });
}
