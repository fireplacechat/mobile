import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

class _ConfirmedWithoutHistory extends FixtureChat {
  @override
  Future<SendOutcome> checkSendStatus(String chatId, String messageId) async =>
      SendOutcome.confirmed;
  @override
  Future<void> saveSentLocally({
    required String chatId,
    required String messageId,
    required String body,
    required DateTime sentAt,
  }) async {
    throw StateError('history cannot save');
  }
}

void main() {
  testWidgets('account loss hides the forwarding preview and recipients', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    AppSession? session = f.session;
    final overrides = f.overrides..removeAt(0);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          appSessionProvider.overrideWith((ref) async => session),
          ...overrides,
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: ForwardMessageScreen(
            message: message(
              id: 'private-forward',
              body: 'private forwarding preview',
              outgoing: true,
            ),
          ),
        ),
      ),
    );
    await settleUi(t);
    expect(find.text('private forwarding preview'), findsOneWidget);
    final c = ProviderScope.containerOf(
      t.element(find.byType(ForwardMessageScreen)),
    );
    session = null;
    c.invalidate(appSessionProvider);
    await settleUi(t);
    expect(find.text('private forwarding preview'), findsNothing);
    expect(find.byKey(const Key('forwardSend')), findsNothing);
    expect(find.text('This account is no longer available.'), findsOneWidget);
    expect(f.chat.sends, isEmpty);
  });
  testWidgets(
    'confirmed unsaved send keeps its known-published warning across routes',
    (t) async {
      final f = UiFixture(chat: _ConfirmedWithoutHistory());
      await f.seed();
      addTearDown(f.session.close);
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChatScreen(chatId: 'alice_bob'),
                    ),
                  ),
                  child: const Text('Open Bob'),
                ),
              ),
            ),
          ),
        ),
      );
      await settleUi(t);
      final c = ProviderScope.containerOf(t.element(find.byType(Scaffold)));
      c
          .read(pendingLocalSendsProvider.notifier)
          .add(
            SendNotConfirmedException(
              outcome: SendOutcome.publishUnknown,
              chatId: 'alice_bob',
              messageId: 'unsaved-confirmed',
              body: 'known on server',
              attemptedAt: fixtureTime,
              persisted: false,
            ),
            ownerUid: 'alice',
          );
      await t.tap(find.text('Open Bob'));
      await t.pumpAndSettle();
      await settleUi(t);
      await t.tap(find.byKey(const Key('checkSendStatus')));
      await settleUi(t);
      expect(
        c.read(pendingLocalSendsProvider).values.single.outcome,
        SendOutcome.publishedLocalSaveFailed,
      );
      await t.tap(find.byKey(const Key('chatBack')));
      await t.pumpAndSettle();
      await t.tap(find.text('Open Bob'));
      await t.pumpAndSettle();
      await settleUi(t);
      expect(find.text('Sent — could not save on this device'), findsOneWidget);
      expect(find.byKey(const Key('resendUnconfirmed')), findsNothing);
      expect(f.chat.sends, isEmpty);
    },
  );

  testWidgets(
    'account loss hides unsaved plaintext and clears the old composer',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      AppSession? session = f.session;
      final overrides = f.overrides..removeAt(0);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            appSessionProvider.overrideWith((ref) async => session),
            ...overrides,
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const ChatScreen(chatId: 'alice_fred'),
          ),
        ),
      );
      await settleUi(t);
      await t.enterText(find.byKey(const Key('composer')), 'private draft');
      final c = ProviderScope.containerOf(t.element(find.byType(ChatScreen)));
      c
          .read(pendingLocalSendsProvider.notifier)
          .add(
            SendNotConfirmedException(
              outcome: SendOutcome.publishUnknown,
              chatId: 'alice_fred',
              messageId: 'private-warning',
              body: 'unsaved private body',
              attemptedAt: fixtureTime,
              persisted: false,
            ),
            ownerUid: 'alice',
          );
      await settleUi(t);
      expect(find.text('unsaved private body'), findsOneWidget);
      session = null;
      c.invalidate(appSessionProvider);
      await settleUi(t);
      expect(find.text('unsaved private body'), findsNothing);
      expect(find.byKey(const Key('composer')), findsNothing);
      expect(find.text('Return to your chats'), findsOneWidget);
    },
  );

  testWidgets(
    'unsaved uncertain forward keeps warning in destination after leaving picker',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      f.chat.sendError = SendNotConfirmedException(
        outcome: SendOutcome.publishUnknown,
        chatId: 'alice_bob',
        messageId: 'unsaved',
        body: 'Forwarded body',
        attemptedAt: fixtureTime,
        persisted: false,
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: ForwardMessageScreen(
              message: message(
                id: 'source',
                body: 'Forwarded body',
                outgoing: true,
              ),
            ),
          ),
        ),
      );
      await settleUi(t);
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
      await t.pump();
      await t.tap(find.byKey(const Key('forwardSend')));
      await settleUi(t);
      final context = t.element(find.byType(ForwardMessageScreen));
      final c = ProviderScope.containerOf(context);
      expect(
        c.read(pendingLocalSendsProvider).values.single.messageId,
        'unsaved',
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ChatScreen(chatId: 'alice_bob'),
        ),
      );
      await t.pumpAndSettle();
      await settleUi(t);
      expect(find.text('Forwarded body'), findsOneWidget);
      expect(find.text('Message not confirmed'), findsOneWidget);
      expect(f.chat.sends, ['Forwarded body']);
    },
  );
  test(
    'changing account clears pending plaintext and does not cross chat IDs',
    () async {
      final f = UiFixture();
      addTearDown(f.session.close);
      AppSession? session = f.session;
      final overrides = f.overrides..removeAt(0);
      final c = ProviderContainer(
        overrides: [
          appSessionProvider.overrideWith((ref) async => session),
          ...overrides,
        ],
      );
      addTearDown(c.dispose);
      c.listen(pendingLocalSendsProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      c
          .read(pendingLocalSendsProvider.notifier)
          .add(
            SendNotConfirmedException(
              outcome: SendOutcome.publishUnknown,
              chatId: 'alice_fred',
              messageId: 'same-id',
              body: 'private',
              attemptedAt: fixtureTime,
              persisted: false,
            ),
            ownerUid: 'alice',
          );
      c
          .read(pendingLocalSendsProvider.notifier)
          .confirmed('alice_fred', 'same-id', ownerUid: 'alice');
      expect(
        c.read(pendingLocalSendsProvider).values.single.outcome,
        SendOutcome.publishedLocalSaveFailed,
      );
      c.read(pendingLocalSendsProvider.notifier).remove('alice_bob', 'same-id');
      expect(c.read(pendingLocalSendsProvider), hasLength(1));
      session = null;
      c.invalidate(appSessionProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(pendingLocalSendsProvider), isEmpty);
    },
  );
}
