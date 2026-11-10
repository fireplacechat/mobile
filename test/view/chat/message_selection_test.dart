import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/message_selection.dart';

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
    expect(find.text('1 selected'), findsOneWidget);
    await t.tap(bubble('4'));
    await t.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await t.tap(find.byKey(const Key('deleteSelectedMessages')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
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
    await t.tap(find.byKey(const Key('composer')));
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
}
