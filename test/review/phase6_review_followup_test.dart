import 'dart:async';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/account_deletion_screens.dart';
import 'package:fireplace/src/ui/legal_links.dart';
import 'package:fireplace/src/ui/recovery_screens.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/account_fixture.dart';
import '../support/ui_fixture.dart';

Future<void> showRecovery(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final f = UiFixture();
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...f.overrides,
        recoveryServiceProvider.overrideWithValue(ActionRecovery()),
      ],
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: const RecoveryKeyScreen(),
      ),
    ),
  );
  await settleUi(t);
  await t.tap(find.byKey(const Key('createRecovery')));
  await settleUi(t);
}

void mockClipboard(
  WidgetTester t,
  Future<Object?> Function(MethodCall) handler,
) {
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    handler,
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  testWidgets(
    'recovery copy failure stays private and retry confirms copying without marking saved',
    (t) async {
      var fail = true;
      String? copied;
      mockClipboard(t, (call) async {
        if (call.method == 'Clipboard.setData') {
          if (fail) {
            throw PlatformException(code: 'failed', message: 'PRIVATE DETAIL');
          }
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      await showRecovery(t);
      await t.tap(find.byKey(const Key('copyRecoveryKey')));
      await t.pumpAndSettle();
      expect(find.textContaining('Could not copy the key'), findsOneWidget);
      expect(find.textContaining('PRIVATE DETAIL'), findsNothing);
      expect(find.text('Recovery key copied'), findsNothing);
      fail = false;
      await t.tap(find.byKey(const Key('copyRecoveryKey')));
      await t.pumpAndSettle();
      expect(find.text('Recovery key copied'), findsOneWidget);
      expect(find.textContaining('Could not copy the key'), findsNothing);
      expect(
        copied,
        t.widget<SelectableText>(find.byKey(const Key('recoveryKeyText'))).data,
      );
      expect(
        t.widget<CheckboxListTile>(find.byKey(const Key('savedCheck'))).value,
        isFalse,
      );
      expect(
        t.widget<FilledButton>(find.byKey(const Key('recoveryDone'))).onPressed,
        isNull,
      );
      expect(
        find.textContaining('Other apps or synced devices'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pending recovery copy guards repeats and completion after disposal',
    (t) async {
      final hold = Completer<void>();
      var copies = 0;
      mockClipboard(t, (call) async {
        if (call.method == 'Clipboard.setData') {
          copies++;
          await hold.future;
        }
        return null;
      });
      await showRecovery(t);
      final copy = t
          .widget<TextButton>(find.byKey(const Key('copyRecoveryKey')))
          .onPressed!;
      copy();
      copy();
      await t.pump();
      expect(copies, 1);
      expect(
        t
            .widget<TextButton>(find.byKey(const Key('copyRecoveryKey')))
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
      hold.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'deletion legal route is guarded and returns to retained confirmation fields',
    (t) async {
      final f = UiFixture();
      addTearDown(f.session.close);
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.dark),
            home: const DeleteAccountScreen(),
          ),
        ),
      );
      await settleUi(t);
      await t.enterText(find.byKey(const Key('confirmUsername')), 'alice');
      await t.enterText(
        find.byKey(const Key('confirmPassword')),
        'example-password',
      );
      final read = t
          .widget<TextButton>(find.byKey(const Key('deletionLegalLinks')))
          .onPressed!;
      read();
      read();
      await t.pumpAndSettle();
      expect(find.byType(LegalLinksScreen), findsOneWidget);
      expect(find.text(privacyPolicyUrl), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('confirmUsername')))
            .controller!
            .text,
        'alice',
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('confirmPassword')))
            .controller!
            .text,
        'example-password',
      );
      expect(
        t
            .widget<TextButton>(find.byKey(const Key('deletionLegalLinks')))
            .onPressed,
        isNotNull,
      );
    },
  );
}
