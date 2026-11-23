import 'package:example_app/pages/plugins_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import '../integration_test/mock_plugins.dart';

void main() {
  late DemoPluginMocks mocks;

  setUp(() {
    mocks = DemoPluginMocks()..install();
  });

  tearDown(() => mocks.restore());

  testWidgets('share validates content and shows the plugin results', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: SharePage(share: mocks.share)));
    await tester.enterText(find.byKey(const ValueKey('share-text')), '');
    await tester.tap(find.byKey(const ValueKey('share-send')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a message to share'), findsOneWidget);
    expect(mocks.sharePlatform.requests, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('share-text')),
      'A message to share',
    );
    for (final message in [
      'Share action selected',
      'Sharing dismissed',
      'Share result unavailable',
    ]) {
      await tester.tap(find.byKey(const ValueKey('share-send')));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
    }
    expect(mocks.sharePlatform.requests, hasLength(3));
    expect(mocks.sharePlatform.requests.first.text, 'A message to share');
    expect(mocks.sharePlatform.requests.first.subject, 'MCP playground');
    expect(
      mocks.sharePlatform.requests.first.sharePositionOrigin!.isEmpty,
      isFalse,
    );
  });

  testWidgets('package info displays the plugin mock values', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PackageInfoPage()));
    await tester.pumpAndSettle();
    expect(find.text('MCP Playground'), findsOneWidget);
    expect(find.text('dev.example.mcp_playground'), findsOneWidget);
    expect(find.text('2.3.4'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('camera permission covers denial, grant, blocking and settings', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PermissionsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Camera: denied'), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-settings')), findsNothing);

    for (final status in ['denied', 'granted', 'permanentlyDenied']) {
      await tester.tap(find.byKey(const ValueKey('permission-request')));
      await tester.pumpAndSettle();
      expect(find.text('Camera: $status'), findsOneWidget);
    }
    expect(mocks.permissions.requests, [
      [Permission.camera],
      [Permission.camera],
      [Permission.camera],
    ]);
    await tester.tap(find.byKey(const ValueKey('permission-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Settings opened'), findsOneWidget);
    expect(mocks.permissions.settingsOpened, 1);

    await tester.tap(find.byKey(const ValueKey('permission-check')));
    await tester.pumpAndSettle();
    expect(find.text('Camera: permanentlyDenied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
