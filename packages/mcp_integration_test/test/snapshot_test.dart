import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_integration_test/src/snapshot.dart';

Future<List<Map<String, Object?>>> _snapshot(WidgetTester tester, Widget body, {int maxNodes = 300}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  return buildSnapshot(tester.binding.rootElement!, maxNodes: maxNodes);
}

Map<String, Object?> _node(List<Map<String, Object?>> nodes, String field, Object value) =>
    nodes.singleWhere((n) => n[field] == value);

void main() {
  testWidgets('describes texts, inputs and buttons with keys, flags and bounds', (tester) async {
    final nodes = await _snapshot(
      tester,
      Column(children: [
        const Text('Login', key: ValueKey('title')),
        TextField(controller: TextEditingController(text: 'eduardo')),
        TextField(obscureText: true, controller: TextEditingController(text: 'secret')),
        FilledButton(key: const ValueKey('login'), onPressed: () {}, child: const Text('Sign in')),
        const FilledButton(key: ValueKey('disabled'), onPressed: null, child: Text('Off')),
        Switch(value: true, onChanged: (_) {}),
      ]),
    );

    final title = _node(nodes, 'key', 'title');
    expect(title['type'], 'Text');
    expect(title['text'], 'Login');
    expect(title.containsKey('tappable'), isFalse);
    expect(title['rect'], isA<List<double>>().having((r) => r.length, 'length', 4));

    expect(_node(nodes, 'text', 'eduardo')['type'], 'EditableText');
    expect(_node(nodes, 'text', 'eduardo')['tappable'], isTrue);
    expect(_node(nodes, 'text', '••••••')['type'], 'EditableText', reason: 'passwords are masked');
    expect(nodes.where((n) => n['text'] == 'secret'), isEmpty);

    expect(_node(nodes, 'key', 'login'), containsPair('enabled', true));
    expect(_node(nodes, 'key', 'login'), containsPair('tappable', true));
    expect(_node(nodes, 'text', 'Sign in')['tappable'], isTrue, reason: 'text inside a button is tappable');
    expect(_node(nodes, 'key', 'disabled'), containsPair('enabled', false));

    final toggle = nodes.singleWhere((n) => n['type'] == 'Switch');
    expect(toggle, containsPair('value', true));
  });

  testWidgets('reports each text once and skips offstage widgets', (tester) async {
    final nodes = await _snapshot(
      tester,
      const Column(children: [Text('Visible'), Offstage(child: Text('Hidden'))]),
    );

    expect(nodes.where((n) => n['text'] == 'Visible'), hasLength(1));
    expect(nodes.where((n) => n['text'] == 'Hidden'), isEmpty);
  });

  testWidgets('stops at maxNodes', (tester) async {
    final nodes = await _snapshot(
      tester,
      Column(children: [for (var i = 0; i < 10; i++) Text('Item $i')]),
      maxNodes: 3,
    );

    expect(nodes, hasLength(3));
  });
}
