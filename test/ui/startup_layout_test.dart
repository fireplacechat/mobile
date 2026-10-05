import 'package:fireplace/src/ui/lockup.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(320, 480),
      const Size(812, 375),
      const Size(430, 932),
    ]) {
      testWidgets(
        'approved lockup and startup actions remain usable $brightness $size at 200%',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var retries = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: fireplaceTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: FireplaceSplash(
                title: 'Account unavailable',
                message: 'Please try again to prepare your account. You can also sign out and sign in again.',
                actions: [
                  FilledButton(
                    key: const Key('retry'),
                    onPressed: () => retries++,
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    key: const Key('signOut'),
                    onPressed: () {},
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(FireplaceLockup), findsOneWidget);
          if (size.width == 812) {
            expect(
              tester.getRect(find.byType(Card)).left,
              greaterThan(tester.getRect(find.byType(FireplaceLockup)).right),
              reason: 'landscape controls sit beside the art instead of covering it',
            );
          }
          expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            brightness == Brightness.dark ? fireplaceCharcoal : fireplaceCream,
          );
          expect(
            find.byType(LinearProgressIndicator),
            findsNothing,
            reason: 'an error is not still loading',
          );
          await tester.ensureVisible(find.byKey(const Key('retry')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('retry')));
          expect(retries, 1);
          await tester.ensureVisible(find.byKey(const Key('signOut')));
          await tester.pump();
          expect(
            tester.getRect(find.byKey(const Key('signOut'))).bottom,
            lessThanOrEqualTo(size.height),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
