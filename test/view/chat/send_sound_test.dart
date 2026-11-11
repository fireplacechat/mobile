import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/model/notifications/system_notifications.dart';
import 'package:fireplace/src/model/settings/send_sound_preference.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';

import '../../support/ui_fixture.dart';

class _System implements SystemNotifications {
  int played = 0;
  @override
  Future<void> setBadge(int count) async {}
  @override
  Future<void> clearDelivered() async {}
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> playSendSound() async => played++;
}

void main() {
  Future<(UiFixture, _System)> mount(WidgetTester t, {bool on = true}) async {
    final f = UiFixture();
    await f.seed();
    if (!on) f.secrets.data[SendSoundPreference.storageKey] = 'off';
    final system = _System();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...f.overrides,
          systemNotificationsProvider.overrideWithValue(system),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          navigatorObservers: [chatRouteObserver],
          home: const ChatScreen(chatId: 'alice_fred'),
        ),
      ),
    );
    await settleUi(t);
    return (f, system);
  }

  Future<void> send(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const Key('composer')), text);
    await t.pump();
    await t.tap(find.byKey(const Key('send')));
    await settleUi(t);
  }

  testWidgets('sending a message plays the send pop once', (t) async {
    final (f, system) = await mount(t);
    await send(t, 'hello');
    expect(f.chat.sends, ['hello']);
    expect(system.played, 1);
  });

  testWidgets('no pop when Send sound is off', (t) async {
    final (f, system) = await mount(t, on: false);
    await send(t, 'hello');
    expect(f.chat.sends, ['hello']);
    expect(system.played, 0);
  });
}
