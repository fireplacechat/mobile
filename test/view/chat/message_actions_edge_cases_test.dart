import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'timeline_composer_test.dart' show pumpChat;
import 'chat_features_test.dart' show mount, container;
import 'long_press_menu_test.dart' show Safety, bubble, action;

Future<UiFixture> fixture(
  WidgetTester t, {
  MessageStatus status = MessageStatus.ok,
}) async {
  final f = UiFixture(safety: Safety());
  await f.seed();
  addTearDown(f.session.close);
  await f.chat.store.add(
    message(
      id: 'target',
      body: '**Only this** message',
      status: status,
      at: fixtureTime.add(const Duration(minutes: 1)),
    ),
  );
  return f;
}

void main() {
  testWidgets('keyboard opens message actions with Shift F10', (t) async {
    final f = await fixture(t);
    await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
    Focus.of(t.element(bubble('target'))).requestFocus();
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.f10);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    expect(action('copy'), findsOneWidget);
    expect(action('report'), findsOneWidget);
  });

  testWidgets('cancelled message report sends nothing', (t) async {
    final f = await fixture(t);
    await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
    await t.longPress(bubble('target'));
    await t.pumpAndSettle();
    await t.tap(action('report'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Cancel'));
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sendReport')), findsNothing);
    expect((f.safety as Safety).reports, isEmpty);
  });

  testWidgets(
    'undecryptable message offers Report without sharing its placeholder',
    (t) async {
      final f = await fixture(t, status: MessageStatus.undecryptable);
      await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
      await t.longPress(bubble('target'));
      await t.pumpAndSettle();
      for (final id in ['copy', 'forward', 'selectText']) {
        expect(action(id), findsNothing);
      }
      await t.tap(action('report'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('reportInclude')));
      await t.tap(find.byKey(const Key('reportInclude')));
      await t.ensureVisible(find.byKey(const Key('sendReport')));
      await t.tap(find.byKey(const Key('sendReport')));
      await settleUi(t);
      expect((f.safety as Safety).reports.single.$3, isEmpty);
    },
  );

  testWidgets('held contact has no message actions', (t) async {
    final f = await fixture(t);
    f.alerts = {
      'fred': [1],
    };
    await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
    await t.longPress(bubble('target'));
    await t.pumpAndSettle();
    for (final id in ['copy', 'forward', 'selectText', 'report']) {
      expect(action(id), findsNothing);
    }
  });

  testWidgets('an open menu cannot copy after the contact is blocked', (
    t,
  ) async {
    final f = await fixture(t);
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
    final c = container(t);
    await t.longPress(bubble('target'));
    await t.pumpAndSettle();
    f.blocked = {'fred'};
    c.invalidate(blockedUidsProvider);
    await settleUi(t);
    await t.tap(action('copy'));
    await t.pumpAndSettle();
    expect(copied, isNull);
    expect(find.text('Conversation hidden'), findsOneWidget);
  });

  testWidgets('selection sheet revokes plaintext when the contact is blocked', (
    t,
  ) async {
    final f = await fixture(t);
    await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
    final c = container(t);
    await t.longPress(bubble('target'));
    await t.pumpAndSettle();
    await t.tap(action('selectText'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selectableMessageText')), findsOneWidget);
    f.blocked = {'fred'};
    c.invalidate(blockedUidsProvider);
    await settleUi(t);
    expect(find.byKey(const Key('selectableMessageText')), findsNothing);
    expect(find.textContaining('Close this sheet'), findsOneWidget);
  });

  testWidgets('screen-reader custom Select text action opens the sheet', (
    t,
  ) async {
    final f = await fixture(t);
    final handle = t.ensureSemantics();
    await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
    final node = t.getSemantics(bubble('target'));
    final ids = node.getSemanticsData().customSemanticsActionIds!;
    expect(
      ids.map((id) => CustomSemanticsAction.getAction(id)!.label).toSet(),
      {'Copy', 'Forward', 'Select text', 'Report'},
    );
    final select = ids.singleWhere(
      (id) => CustomSemanticsAction.getAction(id)!.label == 'Select text',
    );
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      select,
    );
    await t.pumpAndSettle();
    expect(
      t
          .widget<SelectableText>(
            find.byKey(const Key('selectableMessageText')),
          )
          .data,
      'Only this message',
    );
    handle.dispose();
  });

  testWidgets(
    'edge-positioned menu remains usable on a narrow screen at 3x text',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(3)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMessageActionsMenu(
                  context,
                  globalPosition: const Offset(319, 639),
                  actions: [
                    MessageAction(
                      id: 'selectText',
                      label: 'Select text',
                      icon: Icons.text_fields,
                      onSelected: () {},
                    ),
                    MessageAction(
                      id: 'report',
                      label: 'Report',
                      icon: Icons.flag,
                      onSelected: () {},
                    ),
                  ],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.ensureVisible(action('report'));
      await t.pumpAndSettle();
      final rect = t.getRect(action('report'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Select text remains usable with keyboard insets and enlarged text',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = await fixture(t);
      await pumpChat(t, f, scale: 2, keyboard: 220);
      await t.longPress(bubble('target'));
      await t.pumpAndSettle();
      await t.tap(action('selectText'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('selectableMessageText')), findsOneWidget);
      expect(
        t.getRect(find.byKey(const Key('selectableMessageText'))).bottom,
        lessThanOrEqualTo(420),
      );
      expect(t.takeException(), isNull);
    },
  );
}
