import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/notifications/app_badge.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/notifications/system_notifications.dart';

class _FakeSystem implements SystemNotifications {
  final calls = <String>[];
  @override
  Future<void> setBadge(int count) async => calls.add('badge $count');
  @override
  Future<void> clearDelivered() async => calls.add('clear');
  @override
  Future<void> openSettings() async => calls.add('settings');
  @override
  Future<void> playSendSound() async => calls.add('send sound');
}

class _FakeActivity extends ChatActivity {
  _FakeActivity(this.initial);
  final ChatActivityState initial;
  @override
  ChatActivityState build() => initial;
  void set(ChatActivityState next) => state = next;
}

const _signedIn = AsyncData<Object?>('session');

ChatActivityState _activity(
  Map<String, int> unread, {
  Set<String> muted = const {},
  bool loading = false,
}) => ChatActivityState(unread: unread, muted: muted, loading: loading);

void main() {
  group('appBadgeCount', () {
    test('sums unread messages across chats', () {
      expect(appBadgeCount(_signedIn, _activity({'a': 2, 'b': 3})), 5);
    });

    test('muted chats do not count', () {
      expect(
        appBadgeCount(_signedIn, _activity({'a': 2, 'b': 3}, muted: {'b'})),
        2,
      );
    });

    test('keeps the old badge while the session or history loads', () {
      expect(appBadgeCount(const AsyncLoading(), _activity({'a': 1})), isNull);
      expect(
        appBadgeCount(_signedIn, _activity({'a': 1}, loading: true)),
        isNull,
      );
      expect(
        appBadgeCount(
          AsyncError(StateError('x'), StackTrace.empty),
          _activity({}),
        ),
        isNull,
      );
    });

    test('signed out clears the badge', () {
      expect(appBadgeCount(const AsyncData(null), _activity({'a': 4})), 0);
    });
  });

  group('appBadgeProvider', () {
    test('updates the badge on change and clears alerts at zero', () async {
      final system = _FakeSystem();
      final activity = _FakeActivity(_activity({'a': 2}));
      final container = ProviderContainer(
        overrides: [
          appSessionProvider.overrideWithValue(const AsyncData(null)),
          chatActivityProvider.overrideWith(() => activity),
          systemNotificationsProvider.overrideWithValue(system),
        ],
      );
      addTearDown(container.dispose);
      container.read(appBadgeProvider);
      // Signed out: no badge, no stale alerts.
      expect(system.calls, ['badge 0', 'clear']);

      // Repeating the same count does not call the system again.
      activity.set(_activity({'a': 5}));
      expect(system.calls, ['badge 0', 'clear']);
    });

    test('waits for the session before touching the badge', () async {
      final system = _FakeSystem();
      final activity = _FakeActivity(_activity({}, loading: true));
      final container = ProviderContainer(
        overrides: [
          appSessionProvider.overrideWith((ref) async => null),
          chatActivityProvider.overrideWith(() => activity),
          systemNotificationsProvider.overrideWithValue(system),
        ],
      );
      addTearDown(container.dispose);
      container.read(appBadgeProvider);
      // Still loading: nothing changes yet.
      expect(system.calls, isEmpty);
      await container.read(appSessionProvider.future);
      expect(system.calls, ['badge 0', 'clear']);
    });
  });
}
