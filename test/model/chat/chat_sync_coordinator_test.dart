import 'dart:async';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/chat_sync_coordinator.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSafety extends Fake implements SafetyService {
  @override
  final blocked = <String>{};
  final hidden = <String>{};
  int reads = 0;
  Future<void> Function()? beforeHidden;
  @override
  bool isBlocked(String uid) => blocked.contains(uid);
  @override
  Future<Set<String>> hiddenChats() async {
    reads++;
    await beforeHidden?.call();
    return Set.of(hidden);
  }
}

class FakeChat extends Fake implements ChatService {
  final starts = <String>[];
  final cancels = <String>[];
  void Function(String)? onStart;
  @override
  StreamSubscription<void> startSync(String id, {int limit = 50}) {
    onStart?.call(id);
    starts.add(id);
    return StreamController<void>(onCancel: () => cancels.add(id)).stream
        .listen((_) {});
  }
}

ChatSummary summary(String id, {bool incoming = false}) => ChatSummary(
  id,
  id,
  null,
  accepted: !incoming,
  initiator: incoming ? id : 'fred',
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSafety safety;
  late FakeChat chat;
  late MemoryMessageStore store;
  late LocalChatPreferences prefs;
  late ChatSyncCoordinator coordinator;
  var stopped = false;
  void build({Future<void> Function(String)? save, bool baseline = false}) {
    prefs = LocalChatPreferences(save: save, baselineExisting: baseline);
    coordinator = ChatSyncCoordinator(
      uid: 'fred',
      safety: safety,
      chat: chat,
      chatPreferences: prefs,
      store: store,
      isStopped: () => stopped,
    );
    addTearDown(() async {
      await coordinator.stop();
      await prefs.close();
    });
  }

  setUp(() {
    safety = FakeSafety();
    chat = FakeChat();
    store = MemoryMessageStore();
    stopped = false;
  });

  test('only qualifying chats sync, once each', () async {
    build();
    safety.blocked.add('bob');
    safety.hidden.add('sarah');
    coordinator.chatsChanged([
      summary('jeff'),
      summary('bob'),
      summary('sarah'),
      summary('katy', incoming: true),
    ]);
    await flush();
    await coordinator.reconcile();
    expect(chat.starts, ['jeff']);
    safety.blocked.clear();
    coordinator.blockedChanged();
    await flush();
    expect(chat.starts, ['jeff', 'bob']);
    coordinator.chatsChanged([summary('katy')]);
    await flush();
    expect(chat.cancels, ['jeff', 'bob']);
    expect(chat.starts, ['jeff', 'bob', 'katy']);
  });

  test('a newly blocked or hidden chat loses sync', () async {
    build();
    coordinator.chatsChanged([summary('bob'), summary('sarah')]);
    await flush();
    safety.blocked.add('bob');
    safety.hidden.add('sarah');
    await coordinator.reconcile();
    expect(chat.cancels, ['bob', 'sarah']);
  });

  test('stop cancels all subscriptions once', () async {
    build();
    coordinator.chatsChanged([summary('bob'), summary('sarah')]);
    await flush();
    await coordinator.stop();
    await coordinator.stop();
    expect(chat.cancels, ['bob', 'sarah']);
  });

  test('stopped coordinator never reads safety or starts sync', () async {
    build();
    stopped = true;
    coordinator.chatsChanged([summary('bob')]);
    coordinator.blockedChanged();
    await coordinator.reconcile();
    await flush();
    expect(safety.reads, 0);
    expect(chat.starts, isEmpty);
  });

  test('stop state is read again after hidden lookup', () async {
    build();
    final gate = Completer<void>();
    safety.beforeHidden = () => gate.future;
    coordinator.chatsChanged([summary('bob')]);
    stopped = true;
    gate.complete();
    await flush();
    expect(chat.starts, isEmpty);
  });

  test('baseline saves incoming history before starting sync', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    build(
      baseline: true,
      save: (_) async {
        entered.complete();
        await release.future;
      },
    );
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    for (final outgoing in [false, true]) {
      await store.add(
        LocalMessage(
          id: outgoing ? 'sent' : 'received',
          chatId: 'bob',
          senderUid: outgoing ? 'fred' : 'bob',
          senderDevice: 'example',
          outgoing: outgoing,
          sentAt: DateTime.utc(2026),
          body: 'Example',
        ),
      );
    }
    chat.onStart = (_) {
      expect(prefs.seen['bob'], {'received'});
      expect(prefs.needsBaseline('bob'), isFalse);
    };
    coordinator.chatsChanged([summary('bob')]);
    await entered.future;
    expect(chat.starts, isEmpty);
    release.complete();
    await flush();
    expect(chat.starts, ['bob']);
  });

  for (final action in ['block', 'hide', 'stop', 'remove', 'request']) {
    test('$action during baseline prevents starting sync', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      build(
        baseline: true,
        save: (_) async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        },
      );
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      coordinator.chatsChanged([summary('bob')]);
      await entered.future;
      if (action == 'block') safety.blocked.add('bob');
      if (action == 'hide') safety.hidden.add('bob');
      if (action == 'stop') stopped = true;
      if (action == 'remove') coordinator.chatsChanged([]);
      if (action == 'request') {
        coordinator.chatsChanged([summary('bob', incoming: true)]);
      }
      release.complete();
      await flush();
      expect(chat.starts, isEmpty);
    });
  }

  test('a baseline failure does not stop messaging', () async {
    build(baseline: true, save: (_) async => throw StateError('sidecar'));
    coordinator.chatsChanged([summary('bob')]);
    await flush();
    expect(chat.starts, ['bob']);
    expect(prefs.available, isFalse);
  });

  test('listener entry points swallow reconciliation errors', () async {
    build();
    safety.beforeHidden = () async => throw StateError('hidden');
    coordinator.chatsChanged([summary('bob')]);
    coordinator.blockedChanged();
    await flush();
    expect(chat.starts, isEmpty);
    expect(safety.reads, 2);
  });
}
