// Issue 244: a person's profile, opened from anywhere, with a way to message
// them whether or not you have chatted before.
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/profile/person_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<UiFixture> open(
  WidgetTester t,
  String peer, {
  Set<String> blocked = const {},
  ProfileChatHandlers? inChat,
}) async {
  final f = UiFixture();
  await f.seed();
  f.blocked = {...blocked};
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('openProfile'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PersonProfileScreen(
                      peerUid: peer,
                      name: peer,
                      inChat: inChat,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('openProfile')));
  await settleUi(t);
  await t.pumpAndSettle();
  return f;
}

final message = find.byKey(const Key('profileMessage'));

void main() {
  testWidgets('someone you chat with: Message opens that chat', (t) async {
    final f = await open(t, 'fred');
    expect(find.byKey(const Key('profileName')), findsOneWidget);
    // An existing chat also offers Mute and Report.
    expect(find.byKey(const Key('detailsMute')), findsOneWidget);
    expect(find.byKey(const Key('detailsReport')), findsOneWidget);
    await t.tap(message);
    await settleUi(t);
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(t.widget<ChatScreen>(find.byType(ChatScreen)).chatId, 'alice_fred');
    expect(f.chat.starts, isEmpty);
  });

  testWidgets('someone you have never chatted with: Message starts a chat', (
    t,
  ) async {
    final f = await open(t, 'zoe');
    // No chat yet: nothing to mute or report.
    expect(find.byKey(const Key('detailsMute')), findsNothing);
    expect(find.byKey(const Key('detailsReport')), findsNothing);
    expect(find.byKey(const Key('detailsBlock')), findsOneWidget);
    await t.tap(message);
    await settleUi(t);
    await t.pumpAndSettle();
    expect(f.chat.starts, ['zoe']);
    expect(t.widget<ChatScreen>(find.byType(ChatScreen)).chatId, 'alice_zoe');
  });

  testWidgets('a blocked person is offered Unblock instead of Message', (
    t,
  ) async {
    await open(t, 'fred', blocked: {'fred'});
    expect(message, findsNothing);
    expect(find.byKey(const Key('profileUnblock')), findsOneWidget);
    expect(find.byKey(const Key('detailsMute')), findsNothing);
  });

  testWidgets('opened from the chat, Message goes back to it', (t) async {
    final f = await open(
      t,
      'fred',
      inChat: ProfileChatHandlers(
        chatId: 'alice_fred',
        onMute: (_) async {},
        onBlock: () async {},
        onUnblock: () async {},
        onReportSpam: (_) async {},
      ),
    );
    await t.tap(message);
    await t.pumpAndSettle();
    expect(find.byType(PersonProfileScreen), findsNothing);
    expect(find.byKey(const Key('openProfile')), findsOneWidget);
    expect(f.chat.starts, isEmpty);
  });

  testWidgets('a failed start says so plainly and stays on the profile', (
    t,
  ) async {
    final failing = _FailingStart();
    await failing.seed();
    addTearDown(failing.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: failing.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const PersonProfileScreen(peerUid: 'zoe', name: 'zoe'),
        ),
      ),
    );
    await settleUi(t);
    await t.tap(message);
    await settleUi(t);
    await t.pumpAndSettle();
    expect(find.text('Could not start chat. Try again.'), findsOneWidget);
    expect(find.byType(PersonProfileScreen), findsOneWidget);
  });
}

class _FailingStart extends UiFixture {
  _FailingStart() : super(chat: _NoStart());
}

class _NoStart extends FixtureChat {
  @override
  Future<String> startChat(String username) async => throw StateError('down');
}
