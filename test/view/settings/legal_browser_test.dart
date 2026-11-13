import 'dart:async';

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const browserChannel = MethodChannel('fireplace/browser');
const privacy = Key('openPrivacyPolicy');
const terms = Key('openTermsOfUse');
const errorText = 'Could not open your browser. Try again.';

Future<void> openPage(WidgetTester tester) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      theme: fireplaceTheme(Brightness.light),
      home: const LegalLinksScreen(),
    ),
  ),
);

void mockBrowser(
  WidgetTester tester,
  Future<Object?> Function(MethodCall) handler,
) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    browserChannel,
    handler,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      browserChannel,
      null,
    ),
  );
}

void main() {
  testWidgets('legal buttons open the exact existing URLs without copying', (
    tester,
  ) async {
    final opened = <String>[];
    mockBrowser(tester, (call) async {
      expect(call.method, 'open');
      opened.add(call.arguments as String);
      return true;
    });
    await openPage(tester);
    expect(find.byKey(privacy), findsOneWidget);
    expect(find.byKey(terms), findsOneWidget);
    expect(find.byTooltip('Copy privacy policy link'), findsNothing);
    expect(find.byTooltip('Copy terms of use link'), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.textContaining('Copy a link'), findsNothing);
    await tester.tap(find.byKey(privacy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(terms));
    await tester.pumpAndSettle();
    expect(opened, [
      'https://fireplacechat.com/privacy/',
      'https://fireplacechat.com/terms/',
    ]);
    expect(find.text(errorText), findsNothing);
  });

  for (final failure in [false, null, 'platform', 'missing']) {
    testWidgets('browser failure $failure keeps the page and allows retry', (
      tester,
    ) async {
      var fail = true;
      var attempts = 0;
      mockBrowser(tester, (call) async {
        attempts++;
        if (!fail) return true;
        if (failure == 'platform') {
          throw PlatformException(code: 'blocked', message: 'PRIVATE DETAIL');
        }
        if (failure == 'missing') throw MissingPluginException();
        return failure;
      });
      await openPage(tester);
      await tester.tap(find.byKey(privacy));
      await tester.pumpAndSettle();
      expect(find.text(errorText), findsOneWidget);
      expect(find.textContaining('PRIVATE DETAIL'), findsNothing);
      expect(find.byKey(privacy), findsOneWidget);
      expect(find.byKey(terms), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(privacy)).onPressed,
        isNotNull,
      );
      fail = false;
      await tester.tap(find.byKey(terms));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text(errorText), findsNothing);
    });
  }

  testWidgets(
    'opening guards repeated taps and safely finishes after disposal',
    (tester) async {
      final hold = Completer<bool>();
      var attempts = 0;
      mockBrowser(tester, (call) {
        attempts++;
        return hold.future;
      });
      await openPage(tester);
      final action = tester
          .widget<OutlinedButton>(find.byKey(privacy))
          .onPressed!;
      action();
      action();
      await tester.pump();
      expect(attempts, 1);
      for (final key in [privacy, terms]) {
        expect(
          tester.widget<OutlinedButton>(find.byKey(key)).onPressed,
          isNull,
        );
      }
      await tester.pumpWidget(const SizedBox());
      hold.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
