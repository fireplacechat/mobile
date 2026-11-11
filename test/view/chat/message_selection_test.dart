import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_selection.dart';
import 'package:fireplace/src/view/chat/message_selection_mark.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat, bubble, action;
import 'chat_features_test.dart' show container;

Future<void> select(WidgetTester t, String id) async {
  await t.longPress(bubble(id));
  await t.pumpAndSettle();
  await t.ensureVisible(action('select'));
  await t.tap(action('select'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('select, toggle, cancel and delete only on this device', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await select(t, '5');
    expect(find.text('1 Selected'), findsOneWidget);
    await t.tap(bubble('4'));
    await t.pumpAndSettle();
    expect(find.text('2 Selected'), findsOneWidget);
    await t.tap(find.byKey(const Key('deleteSelectedMessages')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cancelMessageDelete')));
    await t.pumpAndSettle();
    expect(await f.chat.store.get('alice_fred', '5'), isNotNull);
    await t.tap(find.byKey(const Key('deleteSelectedMessages')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('confirmDeleteForMe')));
    await t.tap(find.byKey(const Key('confirmDeleteForMe')));
    await t.pumpAndSettle();
    expect(await f.chat.store.get('alice_fred', '5'), isNull);
    expect(await f.chat.store.get('alice_fred', '4'), isNull);
    expect(await f.chat.store.get('alice_fred', '3'), isNotNull);
    expect(bubble('5'), findsNothing);
    expect(find.byKey(const Key('selectionCount')), findsNothing);
    expect(f.chat.sends, isEmpty);
  });

  testWidgets('back and background exit without deleting', (t) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await select(t, '5');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selectionCount')), findsNothing);
    await select(t, '5');
    await t.tapAt(const Offset(200, 100));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selectionCount')), findsNothing);
    expect(await f.chat.store.get('alice_fred', '5'), isNotNull);
    await select(t, '5');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selectionCount')), findsNothing);
  });

  testWidgets('selection resets when account or access changes', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await select(t, '5');
    final c = container(t);
    expect(c.read(messageSelectionProvider('alice_fred')).ids, {'5'});
    f.blocked = {'fred'};
    c.invalidate(blockedUidsProvider);
    await settleUi(t);
    expect(c.read(messageSelectionProvider('alice_fred')).ids, isEmpty);
    expect(find.text('Conversation hidden'), findsOneWidget);
  });

  testWidgets('selection marks are circles in the theme accent', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await select(t, '5');
    expect(find.byType(Checkbox), findsNothing);
    final marks = t.widgetList<MessageSelectionMark>(
      find.byType(MessageSelectionMark),
    );
    expect(marks.any((mark) => mark.selected), isTrue);
    expect(marks.any((mark) => !mark.selected), isTrue);
    expect(find.text('Delete All'), findsOneWidget);
    expect(find.byKey(const Key('forwardSelectedMessages')), findsOneWidget);
  });

  testWidgets('delete all deletes messages you sent for everyone', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await f.chat.store.add(
      message(
        id: '6',
        outgoing: true,
        body: 'Still sending',
        status: MessageStatus.unconfirmed,
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    await openChat(t, f);
    await select(t, '5');
    await t.tap(find.byKey(const Key('deleteAllMessages')));
    await t.pumpAndSettle();
    expect(find.text('Delete all messages in the chat?'), findsOneWidget);
    expect(
      find.text(
        'Messages you sent are deleted for everyone. Their messages are removed only on this device.',
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('cancelDeleteAll')));
    await t.pumpAndSettle();
    expect(await f.chat.store.get('alice_fred', '5'), isNotNull);
    expect(f.chat.remoteDeletes, isEmpty);
    await t.tap(find.byKey(const Key('deleteAllMessages')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('confirmDeleteAllMessages')));
    await t.tap(find.byKey(const Key('confirmDeleteAllMessages')));
    await t.pumpAndSettle();
    for (final id in ['1', '3', '5', '6']) {
      expect(await f.chat.store.get('alice_fred', id), isNull, reason: id);
    }
    for (final id in ['2', '4']) {
      final saved = await f.chat.store.get('alice_fred', id);
      expect(saved?.remotelyDeleted, isTrue, reason: id);
      expect(saved?.body, isEmpty, reason: id);
    }
    expect(f.chat.remoteDeletes, ['2', '4']);
    expect(find.text('Of course. I can bring dessert.'), findsNothing);
    expect(find.text('Are we still on for Saturday?'), findsNothing);
    expect(find.text('Still sending'), findsNothing);
    expect(find.byKey(const Key('selectionCount')), findsNothing);
  });

  testWidgets('delete all stops when deleting a sent message fails', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    f.chat.controlError = Exception('offline');
    await openChat(t, f);
    await select(t, '5');
    await t.tap(find.byKey(const Key('deleteAllMessages')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('confirmDeleteAllMessages')));
    await t.tap(find.byKey(const Key('confirmDeleteAllMessages')));
    await t.pumpAndSettle();
    expect(f.chat.remoteDeletes, isEmpty);
    expect(await f.chat.store.get('alice_fred', '1'), isNull);
    expect(await f.chat.store.get('alice_fred', '2'), isNotNull);
    expect(await f.chat.store.get('alice_fred', '4'), isNotNull);
    expect(find.text('Could not make this change. Try again.'), findsOneWidget);
    expect(find.text('Of course. I can bring dessert.'), findsOneWidget);
  });

  testWidgets('delete all actions stay above an open keyboard', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.view.viewInsets = const FakeViewPadding(bottom: 220);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await select(t, '5');
    await t.tap(find.byKey(const Key('deleteAllMessages')));
    await t.pumpAndSettle();
    final limit = 640 - 220;
    for (final key in ['confirmDeleteAllMessages', 'cancelDeleteAll']) {
      final rect = t.getRect(find.byKey(Key(key)));
      expect(rect.top, greaterThanOrEqualTo(0), reason: key);
      expect(rect.bottom, lessThanOrEqualTo(limit), reason: key);
    }
  });
}
