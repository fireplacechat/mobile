// Holding a conversation in the chat list (issue 123): mute, mark read,
// block, and delete on this phone.
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/action_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'chat_tile_layout_test.dart' show pumpList, row, unread;

void main() {
  Future<UiFixture> open(WidgetTester t) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f);
    return f;
  }

  Future<void> hold(WidgetTester t, String chat) async {
    await t.longPress(row(chat));
    await t.pumpAndSettle();
  }

  testWidgets('a long press offers mute, mark read, block and delete', (
    t,
  ) async {
    await open(t);
    await hold(t, 'alice_fred');
    for (final label in ['Mute chat', 'Mark read', 'Block', 'Delete']) {
      expect(find.text(label), findsOneWidget);
    }
    // Above the list, the end of the conversation as a preview.
    expect(
      find.descendant(
        of: find.byKey(const Key('chatRowPreview')),
        matching: find.text('Around two? There is no rush.'),
      ),
      findsOneWidget,
    );
    // Each action has its icon.
    expect(
      find.descendant(
        of: find.byKey(const Key('chatRowMenu')),
        matching: find.byType(Icon),
      ),
      findsNWidgets(4),
    );
    // The bin of the held-message menu, as everywhere (issue 212).
    expect(
      find.descendant(
        of: find.byKey(const Key('chatRowMenu')),
        matching: find.byIcon(ActionIcons.delete),
      ),
      findsOneWidget,
    );
    // Nothing that tells the other person anything.
    expect(find.textContaining('receipt'), findsNothing);
  });

  testWidgets('the keyboard shortcut opens the same menu', (t) async {
    await open(t);
    Focus.of(
      t.element(
        find
            .descendant(of: row('alice_fred'), matching: find.byType(Padding))
            .first,
      ),
    ).requestFocus();
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.f10);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
  });

  testWidgets('mark read clears the count on this phone, and is not offered '
      'when nothing is unread', (t) async {
    final f = await open(t);
    expect(unread('alice_fred'), findsOneWidget);
    final sentBefore = f.chat.sends.length;
    await hold(t, 'alice_fred');
    await t.tap(find.text('Mark read'));
    await t.pumpAndSettle();
    await settleUi(t);
    expect(unread('alice_fred'), findsNothing);
    final container = ProviderScope.containerOf(t.element(row('alice_fred')));
    expect(container.read(chatActivityProvider).unread['alice_fred'], 0);
    // Local only: nothing was sent.
    expect(f.chat.sends.length, sentBefore);
    await hold(t, 'alice_fred');
    expect(find.text('Mark read'), findsNothing);
    expect(find.text('Mute chat'), findsOneWidget);
  });

  testWidgets('block asks with the usual block question first', (t) async {
    await open(t);
    await hold(t, 'alice_fred');
    await t.tap(find.text('Block'));
    await t.pumpAndSettle();
    expect(find.text('Block fred?'), findsOneWidget);
    await t.tap(find.byKey(const Key('cancelBlock')));
    await t.pumpAndSettle();
    expect(row('alice_fred'), findsOneWidget);
  });

  testWidgets('delete asks first; cancelling keeps the conversation', (
    t,
  ) async {
    final f = await open(t);
    await hold(t, 'alice_fred');
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.text('Delete chat on this phone?'), findsOneWidget);
    await t.tap(find.byKey(const Key('cancelDeleteChat')));
    await t.pumpAndSettle();
    expect(row('alice_fred'), findsOneWidget);
    expect(f.chat.cleared, isEmpty);
    expect(await f.chat.store.get('alice_fred', '5'), isNotNull);
  });

  testWidgets('delete removes the conversation and its messages from this '
      'phone, and a new message brings it back', (t) async {
    final f = await open(t);
    await hold(t, 'alice_fred');
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmDeleteChat')));
    await t.pumpAndSettle();
    await settleUi(t);
    expect(row('alice_fred'), findsNothing);
    expect(row('alice_bob'), findsOneWidget);
    expect(f.chat.cleared, {'alice_fred'});
    for (final id in ['1', '2', '3', '4', '5']) {
      expect(await f.chat.store.get('alice_fred', id), isNull);
    }
    // An old message seen again is not taken for a new one.
    expect(await f.chat.store.has('alice_fred', '5'), isTrue);
    // Local only.
    expect(f.chat.remoteDeletes, isEmpty);

    await f.chat.store.add(message(id: 'new', body: 'Are you there?'));
    await settleUi(t);
    expect(row('alice_fred'), findsOneWidget);
    expect(find.text('Are you there?'), findsOneWidget);
  });

  testWidgets('a screen reader gets the same actions', (t) async {
    await open(t);
    final semantics = t.ensureSemantics();
    await t.pump();
    final labels = t
        .getSemantics(row('alice_fred'))
        .getSemanticsData()
        .customSemanticsActionIds!
        .map((id) => CustomSemanticsAction.getAction(id)!.label)
        .toSet();
    expect(labels, containsAll(['Mute chat', 'Mark read', 'Block', 'Delete']));
    semantics.dispose();
  });
}
