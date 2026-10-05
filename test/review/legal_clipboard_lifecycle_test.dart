import 'dart:async';

import 'package:fireplace/src/ui/legal_links.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'clipboard failure is safe and selectable URLs remain available for retry',
    (t) async {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'failed', message: 'PRIVATE DETAIL');
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const LegalLinksScreen(),
        ),
      );
      await t.tap(find.byKey(const Key('copyLink-privacy')));
      await t.pumpAndSettle();
      expect(find.textContaining('Could not copy the link'), findsOneWidget);
      expect(find.textContaining('PRIVATE DETAIL'), findsNothing);
      expect(find.text(privacyPolicyUrl), findsOneWidget);
      expect(
        t
            .widget<IconButton>(find.byKey(const Key('copyLink-privacy')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'clipboard operation guards repeated taps and safe completion after disposal',
    (t) async {
      final hold = Completer<void>();
      var copies = 0;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copies++;
            await hold.future;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: fireplaceTheme(Brightness.dark),
          home: const LegalLinksScreen(),
        ),
      );
      final action = t
          .widget<IconButton>(find.byKey(const Key('copyLink-privacy')))
          .onPressed!;
      action();
      action();
      await t.pump();
      expect(copies, 1);
      expect(
        t
            .widget<IconButton>(find.byKey(const Key('copyLink-privacy')))
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
      hold.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
