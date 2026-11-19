// The in-app message banner (issue 233): it falls in from the top, shows the
// sender's avatar, name and the start of the message, goes when swiped up,
// and with previews off names nobody.
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/notifications/in_app_banner.dart';
import 'package:fireplace/src/view/notifications/in_app_notice.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

final notice = find.byKey(const Key('inAppNotification'));

Future<UiFixture> open(WidgetTester t, {bool previews = true}) async {
  final f = UiFixture();
  await f.seed();
  addTearDown(f.session.close);
  await f.session.chatPreferences.previews(previews);
  final key = GlobalKey<NavigatorState>();
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        navigatorKey: key,
        navigatorObservers: [chatRouteObserver],
        theme: fireplaceTheme(Brightness.light),
        builder: (context, child) =>
            InAppNoticeHost(navigatorKey: key, child: child!),
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
  return f;
}

Future<void> arrive(WidgetTester t, UiFixture f, String id) async {
  await f.chat.store.add(
    message(
      id: id,
      body: 'See you in the garden',
      at: fixtureTime.add(const Duration(minutes: 1)),
    ),
  );
  await settleUi(t);
}

void main() {
  testWidgets('falls in from above the top of the screen', (t) async {
    final f = await open(t);
    await arrive(t, f, 'one');
    await t.pumpAndSettle();
    final rest = t.getTopLeft(notice).dy;
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(notice, findsNothing);

    await arrive(t, f, 'two');
    // settleUi pumps a few frames; the fall takes longer.
    expect(t.getTopLeft(notice).dy, lessThan(rest));
    await t.pumpAndSettle();
    expect(t.getTopLeft(notice).dy, rest);
  });

  testWidgets('shows who, the message and an avatar', (t) async {
    final f = await open(t);
    await arrive(t, f, 'one');
    await t.pumpAndSettle();
    final banner = find.byType(InAppBanner);
    expect(
      find.descendant(of: banner, matching: find.text('fred')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner, matching: find.text('See you in the garden')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner, matching: find.byType(PersonAvatar)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsNothing, reason: 'swipe instead');
  });

  testWidgets('with previews off it names nobody', (t) async {
    final f = await open(t, previews: false);
    await arrive(t, f, 'one');
    await t.pumpAndSettle();
    final banner = find.byType(InAppBanner);
    expect(
      find.descendant(of: banner, matching: find.text('New message')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner, matching: find.text('fred')),
      findsNothing,
    );
    expect(find.descendant(of: banner, matching: find.text('F')), findsNothing);
    expect(
      find.descendant(of: banner, matching: find.byType(FireplaceLogo)),
      findsOneWidget,
    );
  });

  testWidgets('swiping up sends it away; a small push springs back', (t) async {
    final f = await open(t);
    await arrive(t, f, 'one');
    await t.pumpAndSettle();
    final rest = t.getTopLeft(notice).dy;
    // Slowly, then held: not a flick.
    final push = await t.startGesture(t.getCenter(notice));
    for (var i = 0; i < 5; i++) {
      await push.moveBy(const Offset(0, -4));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump(const Duration(milliseconds: 300));
    await push.up();
    await t.pumpAndSettle();
    expect(t.getTopLeft(notice).dy, rest);
    await t.drag(notice, const Offset(0, -80));
    await t.pumpAndSettle();
    expect(notice, findsNothing);
  });

  testWidgets('more messages while it shows add up in one banner', (t) async {
    final f = await open(t);
    await arrive(t, f, 'one');
    await t.pumpAndSettle();
    await arrive(t, f, 'two');
    await t.pumpAndSettle();
    expect(find.byType(InAppBanner), findsOneWidget);
    expect(
      find.descendant(of: find.byType(InAppBanner), matching: find.text('2')),
      findsOneWidget,
    );
  });
}
