import 'package:example_app/demo_api.dart';
import 'package:example_app/main.dart';
import 'package:example_app/pages/api_page.dart';
import 'package:example_app/pages/errors_page.dart';
import 'package:example_app/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../integration_test/mock_api.dart';

void main() {
  test(
    'API requests the expected URL and decodes an injected response',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://jsonplaceholder.typicode.com/users',
        );
        return http.Response(
          '[{"name":"Test user","email":"test@example.com"}]',
          200,
        );
      });
      addTearDown(client.close);
      final users = await DemoApi(client).fetchUsers();
      expect(users.single.name, 'Test user');
      expect(users.single.email, 'test@example.com');
    },
  );

  test(
    'API reports HTTP failures without trying to parse the response',
    () async {
      final client = MockClient((_) async => http.Response('unavailable', 503));
      addTearDown(client.close);
      await expectLater(
        DemoApi(client).fetchUsers(),
        throwsA(
          isA<DemoApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
    },
  );

  testWidgets('login validation, item navigation and favorite state', (
    tester,
  ) async {
    await tester.pumpWidget(DemoApp(client: createDemoMockClient()));
    await tester.tap(find.byKey(const ValueKey('login')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a username'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('username')), 'Lucas');
    await tester.tap(find.byKey(const ValueKey('login')));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Lucas'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-items')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('item-0')));
    await tester.pumpAndSettle();
    expect(find.text('Item 0 details'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite')));
    await tester.pumpAndSettle();
    expect(find.text('Added to favorites'), findsOneWidget);
  });

  testWidgets(
    'profile validates input and saves the selected notification state',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
      await tester.tap(find.byKey(const ValueKey('save-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Enter a valid email'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Lucas',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-email')),
        'lucas@example.com',
      );
      await tester.tap(find.byKey(const ValueKey('notifications')));
      await tester.tap(find.byKey(const ValueKey('save-profile')));
      await tester.pumpAndSettle();
      expect(
        find.text('Saved Lucas (lucas@example.com) — notifications on'),
        findsOneWidget,
      );
    },
  );

  testWidgets('API shows a handled error and recovers through retry', (
    tester,
  ) async {
    final client = createDemoMockClient();
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(home: ApiPage(api: DemoApi(client))));
    expect(find.byKey(const ValueKey('api-loading')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('lucas@example.com'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('api-error')));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 404'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('load-users')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('api-users')), findsOneWidget);
    expect(find.byKey(const ValueKey('api-failure')), findsNothing);
  });

  testWidgets('overflow is opt-in, deterministic and can be turned off', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ErrorsDemoPage()));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('toggle-overflow')));
    await tester.pumpAndSettle();
    final overflow = tester.takeException();
    expect(overflow, isA<FlutterError>());
    expect(overflow.toString(), contains('overflowed by 80 pixels'));
    await tester.tap(find.byKey(const ValueKey('toggle-overflow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overflow-row')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
