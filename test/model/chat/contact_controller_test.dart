import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/model/chat/contact_controller.dart';

void main() {
  test('contact busy is single-flight and clears on success', () async {
    final c = ContactController(reviewOnce: (_, _) async {});
    final hold = Completer<void>();
    int calls = 0;
    final f = c.contactAction(() {
      calls++;
      return hold.future;
    });
    expect(c.busy, isTrue);
    await c.contactAction(() async {
      calls++;
    });
    expect(calls, 1);
    hold.complete();
    await f;
    expect(c.busy, isFalse);
    expect(c.error, isNull);
    c.dispose();
  });
  test('contact failure uses exact safe wording and restores busy', () async {
    final c = ContactController(reviewOnce: (_, _) async {});
    await c.contactAction(() async => throw StateError('private'));
    expect(c.error, 'Could not update this contact. Try again.');
    expect(c.busy, isFalse);
    await c.contactAction(() async {});
    expect(c.error, isNull);
    c.dispose();
  });
  test('security review is single-flight and clears on success', () async {
    final hold = Completer<void>();
    int calls = 0;
    final c = ContactController(
      reviewOnce: (_, _) {
        calls++;
        return hold.future;
      },
    );
    final f = c.reviewIdentity('fred', [7]);
    expect(c.reviewing, isTrue);
    await c.reviewIdentity('fred', [7]);
    expect(calls, 1);
    hold.complete();
    await f;
    expect(c.reviewing, isFalse);
    c.dispose();
  });
  test('security review failure uses exact safe wording', () async {
    final c = ContactController(
      reviewOnce: (_, _) async => throw StateError('private'),
    );
    await c.reviewIdentity('fred', [7]);
    expect(
      c.error,
      'Could not finish the security review. Check this contact’s security code before continuing. Try again.',
    );
    expect(c.reviewing, isFalse);
    c.dispose();
  });
  test(
    'disposing during contact or review prevents late notifications',
    () async {
      for (final review in [false, true]) {
        final hold = Completer<void>();
        final c = ContactController(reviewOnce: (_, _) => hold.future);
        int notifications = 0;
        c.addListener(() => notifications++);
        final f = review
            ? c.reviewIdentity('fred', [7])
            : c.contactAction(() => hold.future);
        c.dispose();
        final n = notifications;
        hold.completeError(StateError('late'));
        await f;
        expect(notifications, n);
      }
    },
  );
}
