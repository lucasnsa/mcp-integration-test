import 'package:mcp_integration_test_server/src/session_recorder.dart';
import 'package:mcp_integration_test_server/src/test_exporter.dart';
import 'package:test/test.dart';

const _options = ExportOptions(
  description: 'login flow',
  imports: ['package:my_app/main.dart as app'],
  appMain: 'app.main();',
);

String _export(List<RecordedStep> steps, [ExportOptions options = _options]) =>
    generateIntegrationTest(steps, options);

RecordedStep _step(String tool, [Map<String, Object?> args = const {}]) =>
    RecordedStep(tool, args);

void main() {
  group('testFileName', () {
    test('adds the _test suffix once', () {
      expect(testFileName('login_flow'), 'login_flow_test.dart');
      expect(testFileName('login_test'), 'login_test.dart');
    });

    test('rejects names that are not snake_case', () {
      for (final name in ['', 'Login', '1login', 'login-flow', '../x']) {
        expect(() => testFileName(name), throwsArgumentError, reason: name);
      }
    });
  });

  group('generateIntegrationTest', () {
    test('builds a testWidgets that starts the app', () {
      final source = _export([
        _step('tap', {
          'finder': {'key': 'login'},
        }),
      ]);

      expect(source, contains("import 'package:my_app/main.dart' as app;"));
      expect(
        source,
        contains("import 'package:integration_test/integration_test.dart';"),
      );
      expect(
        source,
        contains('Future<void> _startApp() async {\n  app.main();\n}'),
      );
      expect(
        source,
        contains('IntegrationTestWidgetsFlutterBinding.ensureInitialized()'),
      );
      expect(source, contains("testWidgets('login flow', (tester) async {"));
      expect(source, contains('Future<void> _settle('));
    });

    test('emits standard finders', () {
      final source = _export([
        _step('tap', {
          'finder': {'key': 'login'},
        }),
        _step('tap', {
          'finder': {'text': 'Save', 'index': 2},
        }),
        _step('tap', {
          'finder': {'textContaining': 'Hel'},
        }),
        _step('tap', {
          'finder': {'tooltip': 'Back', 'includeOffstage': true},
        }),
      ]);

      expect(
        source,
        contains(
          "await tester.tap(find.byKey(const ValueKey<String>('login')).first);",
        ),
      );
      expect(source, contains("await tester.tap(find.text('Save').at(2));"));
      expect(
        source,
        contains("await tester.tap(find.textContaining('Hel').first);"),
      );
      expect(
        source,
        contains(
          "await tester.tap(find.byTooltip('Back', skipOffstage: false).first);",
        ),
      );
      expect(source, contains("import 'package:flutter/material.dart';"));
    });

    test('matches type, semantics and combined criteria by predicate', () {
      final source = _export([
        _step('tap', {
          'finder': {'type': 'FilledButton'},
        }),
        _step('tap', {
          'finder': {'semanticsLabel': 'Close'},
        }),
        _step('tap', {
          'finder': {'type': 'TextField', 'text': 'abc'},
        }),
      ]);

      expect(
        source,
        contains(
          "find.byWidgetPredicate((w) => w.runtimeType.toString() == 'FilledButton'",
        ),
      );
      expect(
        source,
        contains("(w is Semantics && w.properties.label == 'Close')"),
      );
      expect(
        source,
        contains(
          "_textOf(w) == 'abc' && w.runtimeType.toString() == 'TextField'",
        ),
      );
      expect(source, contains('String? _textOf(Widget w)'));
    });

    test('nests within as find.descendant of the parent target', () {
      final source = _export([
        _step('tap', {
          'finder': {
            'type': 'Checkbox',
            'within': {'key': 'row', 'index': 1},
          },
        }),
      ]);

      expect(
        source,
        contains(
          "find.descendant(of: find.byKey(const ValueKey<String>('row')).at(1), "
          'matching: find.byWidgetPredicate(',
        ),
      );
    });

    test('translates every replayable action', () {
      final source = _export([
        _step('longPress', {
          'finder': {'key': 'a'},
          'settle': false,
        }),
        _step('doubleTap', {
          'finder': {'key': 'a'},
        }),
        _step('tapAt', {'x': 10, 'y': 20.5}),
        _step('enterText', {
          'finder': {'key': 'user'},
          'text': 'eduardo',
          'submit': true,
        }),
        _step('drag', {
          'finder': {'key': 'list'},
          'dx': 0,
          'dy': -300,
          'settleTimeoutMs': 500,
        }),
        _step('fling', {
          'finder': {'key': 'list'},
          'dx': 0,
          'dy': -300,
        }),
        _step('scrollUntilVisible', {
          'finder': {'text': 'Item 40'},
          'maxScrolls': 30,
        }),
        _step('pressBack'),
        _step('sendKey', {'key': 'enter'}),
        _step('pump', {'ms': 250}),
        _step('pumpAndSettle', {}),
        _step('waitFor', {
          'finder': {'text': 'Done'},
          'absent': true,
          'timeoutMs': 2000,
        }),
        _step('app_restart'),
      ]);

      for (final line in [
        "await tester.longPress(find.byKey(const ValueKey<String>('a')).first);\n    await tester.pump();",
        'await tester.pump(kDoubleTapMinTime);',
        'await tester.tapAt(const Offset(10, 20.5));',
        "await tester.enterText(find.byKey(const ValueKey<String>('user')).first, 'eduardo');",
        'await tester.testTextInput.receiveAction(TextInputAction.done);',
        'const Offset(0, -300));\n    await _settle(tester, timeout: const Duration(milliseconds: 500));',
        "await tester.fling(find.byKey(const ValueKey<String>('list')).first, const Offset(0, -300), 1000);",
        "await tester.dragUntilVisible(find.text('Item 40').first, find.byType(Scrollable).first, const Offset(0, -200), maxIteration: 30);",
        'await tester.binding.handlePopRoute();',
        'await tester.sendKeyEvent(LogicalKeyboardKey.enter);',
        'await tester.pump(const Duration(milliseconds: 250));',
        'await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(milliseconds: 10000));',
        "await _waitFor(tester, find.text('Done'), absent: true, timeout: const Duration(milliseconds: 2000));",
        'await tester.pumpWidget(const SizedBox.shrink());\n    await _startApp();',
      ]) {
        expect(source, contains(line));
      }
      expect(source, contains("import 'package:flutter/gestures.dart';"));
      expect(source, contains("import 'package:flutter/services.dart';"));
      expect(source, contains('Future<void> _waitFor('));
    });

    test('translates expectations to flutter_test matchers', () {
      final source = _export([
        _step('expect', {
          'finder': {'text': 'Hello'},
        }),
        _step('expect', {
          'finder': {'key': 'err'},
          'exists': false,
        }),
        _step('expect', {
          'finder': {'type': 'ListTile'},
          'count': 3,
        }),
        _step('expect', {
          'finder': {'key': 'greeting'},
          'text': 'Hi',
        }),
      ]);

      expect(source, contains("expect(find.text('Hello'), findsWidgets);"));
      expect(
        source,
        contains(
          "expect(find.byKey(const ValueKey<String>('err')), findsNothing);",
        ),
      );
      expect(source, contains('findsNWidgets(3));'));
      expect(
        source,
        contains(
          "expect(find.descendant(of: find.byKey(const ValueKey<String>('greeting')).first, "
          "matching: find.text('Hi'), matchRoot: true), findsWidgets);",
        ),
      );
    });

    test('leaves expectations that failed while recording as comments', () {
      final source = _export([
        RecordedStep('expect', {
          'finder': {'text': 'Login'},
        }, failure: 'text == "Login" (index 0): expected to exist'),
      ]);

      expect(source, isNot(contains("expect(find.text('Login')")));
      expect(source, contains('// expect: text == "Login" (index 0)'));
    });

    test('reads enterEnv values from the environment, never inline', () {
      final source = _export([
        _step('enterEnv', {
          'finder': {'key': 'password'},
          'name': 'E2E_PASSWORD',
        }),
      ]);

      expect(source, contains("const String.fromEnvironment('E2E_PASSWORD')"));
      expect(source, contains('--dart-define-from-file'));
    });

    test('escapes strings', () {
      final source = _export([
        _step('enterText', {
          'finder': {'text': r"it's $5 \ ok"},
          'text': 'line1\nline2',
        }),
      ]);

      expect(source, contains(r"find.text('it\'s \$5 \\ ok')"));
      expect(source, contains(r"'line1\nline2'"));
    });

    test('imports only what the steps use', () {
      final source = _export([
        _step('expect', {
          'finder': {'text': 'Hello'},
        }),
      ]);

      expect(source, isNot(contains('package:flutter/material.dart')));
      expect(source, isNot(contains('package:flutter/services.dart')));
      expect(source, isNot(contains('package:flutter/gestures.dart')));
      expect(source, isNot(contains('_waitFor(')));
      expect(source, isNot(contains('_textOf(')));
    });

    test('supports relative imports and multi-line app setup', () {
      final source = _export(
        [_step('pressBack')],
        const ExportOptions(
          description: 'x',
          imports: ['demo_app.dart'],
          appMain: 'setUpMocks();\nstartDemoApp();',
          runCommand: 'flutter test integration_test/x_test.dart -d linux',
        ),
      );

      expect(source, contains("import 'demo_app.dart';"));
      expect(source, contains('  setUpMocks();\n  startDemoApp();\n'));
      expect(
        source,
        contains('// Run: flutter test integration_test/x_test.dart -d linux'),
      );
    });
  });
}
