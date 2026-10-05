import 'dart:async';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/services/chat_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<void> drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test(
    'safety refresh with retained previous data fails closed until settled',
    () async {
      final f = UiFixture();
      await f.seed();
      final c = ProviderContainer(overrides: f.overrides);
      addTearDown(c.dispose);
      addTearDown(f.session.close);
      c.listen(chatActivityProvider, (_, _) {});
      await drain();
      expect(
        c.read(chatActivityProvider).history.containsKey('alice_fred'),
        isTrue,
      );
      final pending = Completer<Set<String>>();
      f.hiddenFuture = pending.future;
      c.invalidate(hiddenChatsProvider);
      await drain();
      expect(c.read(hiddenChatsProvider).isLoading, isTrue);
      expect(
        c.read(chatActivityProvider).history.containsKey('alice_fred'),
        isFalse,
      );
      await f.chat.store.add(message(id: 'during-refresh', body: 'hidden'));
      await drain();
      expect(c.read(chatActivityProvider).arrivals, isEmpty);
      pending.complete({'alice_fred'});
      await drain();
      expect(
        c.read(chatActivityProvider).history.containsKey('alice_fred'),
        isFalse,
      );
    },
  );

  test(
    'initial history unread but silent; late arrival, duplicate and repair',
    () async {
      final f = UiFixture();
      await f.seed();
      final c = ProviderContainer(overrides: f.overrides);
      addTearDown(() {
        c.dispose();
      });
      addTearDown(f.session.close);
      c.listen(chatActivityProvider, (_, _) {});
      await drain();
      expect(c.read(chatActivityProvider).unread['alice_fred'], 3);
      expect(c.read(chatActivityProvider).arrivals, isEmpty);
      await c
          .read(chatActivityProvider.notifier)
          .seen(
            'alice_fred',
            c.read(chatActivityProvider).history['alice_fred']!,
          );
      await drain();
      expect(c.read(chatActivityProvider).unread['alice_fred'], 0);
      // Sent timestamp older than the last opening: still new to this phone.
      final late = message(
        id: 'late',
        body: 'Late arrival',
        at: fixtureTime.subtract(const Duration(days: 10)),
      );
      await f.chat.store.add(late);
      await drain();
      expect(c.read(chatActivityProvider).unread['alice_fred'], 1);
      expect(c.read(chatActivityProvider).arrivals.single.id, 'late');
      c.read(chatActivityProvider.notifier).dismissArrivals();
      await f.chat.store.add(late);
      await drain();
      expect(c.read(chatActivityProvider).arrivals, isEmpty);
      await f.chat.store.add(message(id: 'mine', body: 'own', outgoing: true));
      await drain();
      expect(c.read(chatActivityProvider).unread['alice_fred'], 1);
      expect(c.read(chatActivityProvider).arrivals, isEmpty);
    },
  );
  for (final gate in ['request', 'blocked', 'hidden', 'held']) {
    test('$gate never exposes plaintext to search or alerts', () async {
      final f = UiFixture();
      await f.seed();
      if (gate == 'request') {
        f.chat.summaries = [
          ChatSummary(
            'alice_fred',
            'fred',
            fixtureTime,
            accepted: false,
            initiator: 'fred',
          ),
        ];
      }
      if (gate == 'blocked') f.blocked = {'fred'};
      if (gate == 'hidden') f.hidden = {'alice_fred'};
      if (gate == 'held') {
        f.alerts = {
          'fred': [1],
        };
      }
      final c = ProviderContainer(overrides: f.overrides);
      addTearDown(c.dispose);
      addTearDown(f.session.close);
      c.listen(chatActivityProvider, (_, _) {});
      await drain();
      await f.chat.store.add(message(id: 'new', body: 'secret'));
      await drain();
      expect(
        c.read(chatActivityProvider).history.containsKey('alice_fred'),
        isFalse,
      );
      expect(c.read(chatActivityProvider).arrivals, isEmpty);
      expect(c.read(chatActivityProvider).unread['alice_fred'], isNull);
    });
  }
  test(
    'security hold added after a message revokes queued alert and search',
    () async {
      final f = UiFixture();
      await f.seed();
      final c = ProviderContainer(overrides: f.overrides);
      addTearDown(c.dispose);
      addTearDown(f.session.close);
      c.listen(chatActivityProvider, (_, _) {});
      await drain();
      await f.chat.store.add(message(id: 'new', body: 'secret'));
      await drain();
      expect(c.read(chatActivityProvider).arrivals, hasLength(1));
      f.alerts = {
        'fred': [1],
      };
      c.invalidate(identityAlertsProvider);
      await drain();
      expect(c.read(chatActivityProvider).arrivals, isEmpty);
      expect(
        c.read(chatActivityProvider).history.containsKey('alice_fred'),
        isFalse,
      );
      f.alerts = {};
      c.invalidate(identityAlertsProvider);
      await drain();
      expect(c.read(chatActivityProvider).arrivals, isEmpty);
    },
  );
  test('muted chats still have unread, not included in other total', () async {
    final f = UiFixture();
    await f.seed();
    final c = ProviderContainer(overrides: f.overrides);
    addTearDown(c.dispose);
    addTearDown(f.session.close);
    c.listen(chatActivityProvider, (_, _) {});
    await drain();
    await c.read(chatActivityProvider.notifier).mute('alice_fred', true);
    await drain();
    expect(c.read(chatActivityProvider).unread['alice_fred'], 3);
    expect(c.read(chatActivityProvider).otherUnread('alice_bob'), 0);
    await c.read(chatActivityProvider.notifier).mute('alice_fred', false);
    await drain();
    expect(c.read(chatActivityProvider).otherUnread('alice_bob'), 3);
  });
  test(
    'history error excludes stale bodies, recovery snapshot is silent',
    () async {
      final f = UiFixture();
      await f.seed();
      final stream = StreamController<List<LocalMessage>>.broadcast();
      final c = ProviderContainer(
        overrides: [
          ...f.overrides,
          messagesProvider('alice_fred').overrideWith((ref) => stream.stream),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(stream.close);
      addTearDown(f.session.close);
      c.listen(chatActivityProvider, (_, _) {});
      await drain();
      stream.add([message(id: '1', body: 'secret')]);
      await drain();
      stream.addError(StateError('disk error'));
      await drain();
      expect(
        c.read(chatActivityProvider).history.containsKey('alice_fred'),
        isFalse,
      );
      expect(c.read(chatActivityProvider).failed, contains('alice_fred'));
      stream.add([message(id: '1', body: 'secret')]);
      await drain();
      expect(c.read(chatActivityProvider).arrivals, isEmpty);
      expect(c.read(chatActivityProvider).failed, isEmpty);
    },
  );
  test('sign-out clears all local UI history and queues from memory', () async {
    final f = UiFixture();
    await f.seed();
    AppSession? session = f.session;
    final c = ProviderContainer(overrides: [for (final o in f.overrides) o]);
    // The real auth/session dependency is replaced explicitly for this lifecycle check.
    c.dispose();
    final overrides = f.overrides;
    overrides.removeAt(0);
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWith((ref) async => session),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    addTearDown(f.session.close);
    container.listen(chatActivityProvider, (_, _) {});
    await drain();
    expect(container.read(chatActivityProvider).history, isNotEmpty);
    session = null;
    container.invalidate(appSessionProvider);
    await drain();
    expect(container.read(chatActivityProvider).history, isEmpty);
    expect(container.read(chatActivityProvider).arrivals, isEmpty);
  });
}
