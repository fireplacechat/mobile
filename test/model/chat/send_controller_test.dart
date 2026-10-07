import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/chat/send_controller.dart';
import 'package:fireplace/src/model/chat/memory_pending.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';

final at = DateTime.utc(2026, 10, 7);
SendNotConfirmedException uncertain({
  String id = 'pending',
  bool persisted = false,
}) => SendNotConfirmedException(
  outcome: SendOutcome.publishUnknown,
  chatId: 'alice_fred',
  messageId: id,
  body: 'hello',
  attemptedAt: at,
  persisted: persisted,
);

class PendingRecorder extends PendingLocalSends {
  final items = <String, SendNotConfirmedException>{};
  final events = <String>[];
  @override
  void add(SendNotConfirmedException e, {required String ownerUid}) {
    events.add('add:$ownerUid');
    items[e.messageId] = e;
  }

  @override
  void confirmed(String chat, String id, {required String ownerUid}) {
    events.add('confirmed:$ownerUid');
  }

  @override
  void remove(String chat, String id) {
    events.add('remove:$chat');
    items.remove(id);
  }
}

class ControllerChat extends Fake implements ChatService {
  final sent = <(String, String)>[];
  int checks = 0, resends = 0, saves = 0;
  Object? sendError, checkError, resendError, saveError;
  Completer<void>? sendHold, saveHold;
  Completer<SendOutcome>? checkHold;
  SendOutcome outcome = SendOutcome.confirmed;
  @override
  String peerOf(String chatId) => 'fred';
  @override
  Future<void> sendText(String chatId, String body) async {
    sent.add((chatId, body));
    if (sendHold != null) await sendHold!.future;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<SendOutcome> checkSendStatus(String chatId, String messageId) async {
    checks++;
    if (checkError != null) throw checkError!;
    return checkHold?.future ?? outcome;
  }

  @override
  Future<void> resendUnconfirmed({
    required String chatId,
    required String messageId,
    required String body,
  }) async {
    resends++;
    if (resendError != null) throw resendError!;
  }

  @override
  Future<void> saveSentLocally({
    required String chatId,
    required String messageId,
    required String body,
    required DateTime sentAt,
  }) async {
    saves++;
    if (saveHold != null) await saveHold!.future;
    if (saveError != null) throw saveError!;
  }
}

class Harness {
  final service = ControllerChat();
  final pending = PendingRecorder();
  final events = <String>[];
  String text = 'hello', id = 'alice_fred', uid = 'alice';
  int revision = 0, notifications = 0;
  bool? confirm = true;
  bool disposedScope = false;
  Completer<bool?>? dialogHold;
  Map<String, List<int>> alerts = {};
  late final controller =
      SendController(
        chatId: () => id,
        chat: () => service,
        ownerUid: () => uid,
        pendingSends: () {
          if (disposedScope) throw StateError('disposed ref');
          return pending;
        },
        draft: () => text,
        draftRevision: () => revision,
        clearDraft: () {
          events.add('clear');
          text = '';
        },
        notice: (m) => events.add(m),
        showNewest: () => events.add('latest'),
        reviewIdentity: (peer, pub) async {
          events.add('review:$peer');
        },
        identityAlerts: () => alerts,
        confirmSendAnotherCopy: () async {
          events.add('dialog');
          return dialogHold?.future ?? confirm;
        },
      )..addListener(() {
        notifications++;
      });
  void seed() {
    final e = uncertain();
    pending.add(e, ownerUid: uid);
    controller.rememberMemoryPending(e.messageId, () => MemoryPending(e));
  }
}

void main() {
  test('1 over-limit draft is retained and never sent', () async {
    final h = Harness()..text = 'a' * (maxMessageCharacters + 1);
    await h.controller.send();
    expect(h.controller.sendError, messageLimitError);
    expect(h.service.sent, isEmpty);
    expect(h.text.length, maxMessageCharacters + 1);
  });
  test('2 whitespace does nothing and sets no error', () async {
    final h = Harness()..text = '  ';
    await h.controller.send();
    expect(h.service.sent, isEmpty);
    expect(h.controller.sendError, isNull);
    expect(h.notifications, 0);
  });
  test('3 identity hold refuses send with exact notice', () async {
    final h = Harness()
      ..alerts = {
        'fred': [7],
      };
    await h.controller.send();
    expect(h.events, ['Review the security code change before sending.']);
    expect(h.service.sent, isEmpty);
  });
  test('4 in-flight send suppresses duplicates and restores sending', () async {
    final h = Harness();
    h.service.sendHold = Completer<void>();
    final first = h.controller.send();
    await h.controller.send();
    expect(h.service.sent, hasLength(1));
    expect(h.controller.sending, isTrue);
    h.service.sendHold!.complete();
    await first;
    expect(h.controller.sending, isFalse);
  });
  for (final edited in [false, true]) {
    test(
      '5 success preserves revision semantics edited=$edited and side-effect order',
      () async {
        final h = Harness();
        h.service.sendHold = Completer<void>();
        final f = h.controller.send();
        if (edited) {
          h.text = 'new text';
          h.revision++;
        }
        h.service.sendHold!.complete();
        await f;
        expect(h.text, edited ? 'new text' : '');
        expect(h.events, edited ? ['latest'] : ['clear', 'latest']);
      },
    );
  }
  for (final persisted in [false, true]) {
    test(
      '6 uncertain send persisted=$persisted is not a plain failure',
      () async {
        final h = Harness();
        h.service.sendError = uncertain(persisted: persisted);
        await h.controller.send();
        expect(h.controller.memoryPending.length, persisted ? 0 : 1);
        expect(h.pending.items.length, persisted ? 0 : 1);
        expect(h.controller.sendError, isNull);
        expect(h.events, ['clear', 'latest']);
        expect(h.controller.sending, isFalse);
      },
    );
  }
  test('6 edited draft survives an uncertain send', () async {
    final h = Harness();
    h.service
      ..sendHold = Completer<void>()
      ..sendError = uncertain();
    final f = h.controller.send();
    h.text = 'edited';
    h.revision++;
    h.service.sendHold!.complete();
    await f;
    expect(h.text, 'edited');
    expect(h.events, ['latest']);
  });
  test('7 identity exception starts review and restores sending', () async {
    final h = Harness();
    h.service.sendError = IdentityChangedException('fred', [7]);
    await h.controller.send();
    expect(h.events, ['review:fred']);
    expect(h.controller.sending, isFalse);
  });
  test('8 chat exception retains draft and exposes its message', () async {
    final h = Harness();
    h.service.sendError = ChatException('Refused');
    await h.controller.send();
    expect(h.text, 'hello');
    expect(h.controller.sendError, 'Refused');
    expect(h.controller.sending, isFalse);
  });
  test(
    '9 unexpected failure retains draft with safe uncertainty wording',
    () async {
      final h = Harness();
      h.service.sendError = StateError('secret');
      await h.controller.send();
      expect(h.text, 'hello');
      expect(
        h.controller.sendError,
        'We could not confirm this send. It may have reached them. Check your history before sending again.',
      );
      expect(h.controller.sending, isFalse);
    },
  );
  test('dismissError clears the error and notifies exactly once', () async {
    final h = Harness();
    h.service.sendError = ChatException('Refused');
    await h.controller.send();
    final n = h.notifications;
    h.controller.dismissError();
    expect(h.controller.sendError, isNull);
    expect(h.notifications, n + 1);
  });
  test('11 confirmed repair forgets warning without publishing', () async {
    final h = Harness()..seed();
    await h.controller.checkStatus('pending');
    expect(h.controller.memoryPending, isEmpty);
    expect(h.pending.items, isEmpty);
    expect(h.service.saves, 1);
    expect(h.service.sent, isEmpty);
    expect(h.events, ['Message confirmed: it reached the server.']);
    expect(h.controller.messageActions, isEmpty);
  });
  test('11 failed local repair keeps confirmed memory state', () async {
    final h = Harness()..seed();
    h.service.saveError = StateError('save');
    await h.controller.checkStatus('pending');
    expect(
      h.controller.memoryPending['pending']!.outcome,
      SendOutcome.publishedLocalSaveFailed,
    );
    expect(h.pending.items, hasLength(1));
    expect(h.events, ['Message confirmed: it reached the server.']);
  });
  test(
    '11 uncertain status and failed check retain warning and clear action',
    () async {
      final h = Harness()..seed();
      h.service.outcome = SendOutcome.publishUnknown;
      await h.controller.checkStatus('pending');
      expect(
        h.controller.checkNote['pending'],
        'Still not sure. It may or may not have been delivered.',
      );
      h.service.checkError = StateError('check');
      await h.controller.checkStatus('pending');
      expect(
        h.controller.checkNote['pending'],
        'Could not check yet. Nothing was sent again. Try later.',
      );
      expect(h.controller.messageActions, isEmpty);
      expect(h.service.resends, 0);
    },
  );
  test('11 duplicate recovery action is ignored until completion', () async {
    final h = Harness()..seed();
    h.service.checkHold = Completer<SendOutcome>();
    final f = h.controller.checkStatus('pending');
    await h.controller.checkStatus('pending');
    await h.controller.saveOnDevice(h.controller.memoryPending['pending']!);
    await h.controller.sendAgain('pending', 'hello');
    expect(h.service.checks, 1);
    expect(h.service.saves, 0);
    expect(h.service.resends, 0);
    h.service.checkHold!.complete(SendOutcome.publishUnknown);
    await f;
    expect(h.controller.messageActions, isEmpty);
  });
  test(
    '12 cancel does not resend; explicit confirmation sends once and forgets',
    () async {
      final h = Harness()
        ..seed()
        ..confirm = false;
      await h.controller.sendAgain('pending', 'hello');
      expect(h.service.resends, 0);
      expect(h.controller.memoryPending, hasLength(1));
      h.confirm = true;
      await h.controller.sendAgain('pending', 'hello');
      expect(h.service.resends, 1);
      expect(h.controller.memoryPending, isEmpty);
      expect(h.controller.messageActions, isEmpty);
    },
  );
  test('12 all resend failures preserve exact notes or pending copy', () async {
    final h = Harness()..seed();
    h.service.resendError = uncertain(id: 'new');
    await h.controller.sendAgain('pending', 'hello');
    expect(h.controller.memoryPending.containsKey('new'), isTrue);
    expect(h.pending.items.containsKey('new'), isTrue);
    h.service.resendError = ChatException('Copy refused');
    await h.controller.sendAgain('pending', 'hello');
    expect(h.controller.checkNote['pending'], 'Copy refused');
    h.service.resendError = StateError('private');
    await h.controller.sendAgain('pending', 'hello');
    expect(
      h.controller.checkNote['pending'],
      'The new copy is not confirmed. It may have reached them. Do not send another copy without checking.',
    );
    expect(h.controller.messageActions, isEmpty);
  });
  test('13 local repair only saves, and failure retains warning', () async {
    final h = Harness()..seed();
    h.service.saveError = StateError('save');
    await h.controller.saveOnDevice(h.controller.memoryPending['pending']!);
    expect(
      h.controller.checkNote['pending'],
      'Could not save on this device yet. Your message was sent: do not send it again.',
    );
    h.service.saveError = null;
    await h.controller.saveOnDevice(h.controller.memoryPending['pending']!);
    expect(h.controller.memoryPending, isEmpty);
    expect(h.service.sent, isEmpty);
    expect(h.service.resends, 0);
    expect(h.controller.messageActions, isEmpty);
  });
  for (final error in [
    null,
    uncertain(),
    IdentityChangedException('fred', [7]),
    ChatException('no'),
    StateError('other'),
  ]) {
    test(
      '14 disposed send completion never notifies or calls screen callbacks: $error',
      () async {
        final h = Harness();
        h.service
          ..sendHold = Completer<void>()
          ..sendError = error;
        final f = h.controller.send();
        h.controller.dispose();
        final n = h.notifications;
        h.service.sendHold!.complete();
        await f;
        expect(h.notifications, n);
        expect(h.events, isEmpty);
        expect(h.pending.items, isEmpty);
      },
    );
  }
  test(
    '14 dispose during confirmation suppresses resend and notifications',
    () async {
      final h = Harness()
        ..seed()
        ..dialogHold = Completer<bool?>();
      final f = h.controller.sendAgain('pending', 'hello');
      h.controller.dispose();
      final n = h.notifications;
      h.dialogHold!.complete(true);
      await f;
      expect(h.service.resends, 0);
      expect(h.notifications, n);
      expect(h.events, ['dialog']);
    },
  );
  test('14 documents late confirmed save: unguarded cleanup runs, disposed-ref failure is swallowed', () async {
    final h = Harness()..seed();
    h.service.saveHold = Completer<void>();
    final f = h.controller.checkStatus('pending');
    await Future<void>.delayed(Duration.zero);
    expect(h.service.saves, 1);
    h.controller.dispose();
    h.disposedScope = true;
    final n = h.notifications;
    h.service.saveHold!.complete();
    await f;
    expect(h.notifications, n);
    expect(h.events, isEmpty);
    expect(h.controller.memoryPending, isEmpty);
    expect(h.pending.items, hasLength(1));
  });
  test(
    'getters read the current chat and identity on each invocation',
    () async {
      final h = Harness();
      await h.controller.send();
      h.id = 'alice_bob';
      h.uid = 'new-owner';
      h.text = 'second';
      h.service.sendError = uncertain();
      await h.controller.send();
      expect(h.service.sent, [
        ('alice_fred', 'hello'),
        ('alice_bob', 'second'),
      ]);
      expect(h.pending.events, ['add:new-owner']);
    },
  );
  test('memory maps are read-only and silent mutations never notify', () {
    final h = Harness();
    final c = h.controller;
    final view = c.memoryPending;
    c.rememberMemoryPending('pending', () => MemoryPending(uncertain()));
    expect(view, hasLength(1));
    c.rememberMemoryPending(
      'pending',
      () => throw StateError('must not replace'),
    );
    expect(() => view.clear(), throwsUnsupportedError);
    c.dropMemoryPending('pending');
    expect(view, isEmpty);
    c.rememberMemoryPending('pending', () => MemoryPending(uncertain()));
    c.clearMemoryPending();
    expect(view, isEmpty);
    expect(h.notifications, 0);
    expect(() => c.messageActions.clear(), throwsUnsupportedError);
    expect(() => c.checkNote.clear(), throwsUnsupportedError);
  });
  test('10 sending returns to false after each non-disposed outcome', () async {
    for (final error in [
      null,
      uncertain(),
      IdentityChangedException('fred', [7]),
      ChatException('no'),
      StateError('other'),
    ]) {
      final h = Harness();
      h.service.sendError = error;
      await h.controller.send();
      expect(h.controller.sending, isFalse);
    }
  });
  test('clearMemoryPending changes the map without notifying', () {
    final h = Harness()..seed();
    h.controller.clearMemoryPending();
    expect(h.controller.memoryPending, isEmpty);
    expect(h.notifications, 0);
  });
  test('dropMemoryPending changes the map without notifying', () {
    final h = Harness()..seed();
    h.controller.dropMemoryPending('pending');
    expect(h.controller.memoryPending, isEmpty);
    expect(h.notifications, 0);
  });
  test('rememberMemoryPending changes the map without notifying', () {
    final h = Harness();
    h.controller.rememberMemoryPending(
      'pending',
      () => MemoryPending(uncertain()),
    );
    expect(h.controller.memoryPending, hasLength(1));
    expect(h.notifications, 0);
  });
  test(
    '14 dispose during the status await suppresses all later effects',
    () async {
      final h = Harness()..seed();
      h.service.checkHold = Completer<SendOutcome>();
      final f = h.controller.checkStatus('pending');
      h.controller.dispose();
      final n = h.notifications;
      h.service.checkHold!.complete(SendOutcome.confirmed);
      await f;
      expect(h.service.saves, 0);
      expect(h.events, isEmpty);
      expect(h.notifications, n);
    },
  );
  test('14 dispose during saveOnDevice suppresses guarded cleanup', () async {
    final h = Harness()..seed();
    h.service.saveHold = Completer<void>();
    final f = h.controller.saveOnDevice(h.controller.memoryPending['pending']!);
    h.controller.dispose();
    final n = h.notifications;
    h.service.saveHold!.complete();
    await f;
    expect(h.pending.items, hasLength(1));
    expect(h.controller.memoryPending, hasLength(1));
    expect(h.notifications, n);
  });
}
