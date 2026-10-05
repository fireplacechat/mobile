import 'dart:async';

import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/ui/presentation.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

Future<void> pumpChat(
  WidgetTester t,
  UiFixture f, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  double keyboard = 0,
}) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: const ChatScreen(chatId: 'alice_fred'),
      ),
    ),
  );
  await settleUi(t);
}

String draft(WidgetTester t) =>
    t.widget<TextField>(find.byKey(const Key('composer'))).controller!.text;

void main() {
  testWidgets(
    'empty draft disables send, delayed send is guarded and newer edits survive',
    (t) async {
      final f = UiFixture();
      await pumpChat(t, f);
      expect(
        t.widget<IconButton>(find.byKey(const Key('send'))).onPressed,
        isNull,
      );
      await t.enterText(find.byKey(const Key('composer')), '   ');
      await t.pump();
      expect(
        t.widget<IconButton>(find.byKey(const Key('send'))).onPressed,
        isNull,
      );
      f.chat.sendHold = Completer<void>();
      await t.enterText(find.byKey(const Key('composer')), 'first draft');
      await t.pump();
      final send = t
          .widget<IconButton>(find.byKey(const Key('send')))
          .onPressed!;
      send();
      send();
      await t.pump();
      expect(f.chat.sends, ['first draft']);
      await t.enterText(find.byKey(const Key('composer')), 'new draft');
      f.chat.sendHold!.complete();
      await t.pump();
      expect(draft(t), 'new draft');
      expect(
        t.widget<IconButton>(find.byKey(const Key('send'))).onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'unchanged success clears draft, rejection retains it, disposal is safe',
    (t) async {
      final f = UiFixture();
      await pumpChat(t, f);
      await t.enterText(find.byKey(const Key('composer')), 'hello');
      await t.pump();
      await t.tap(find.byKey(const Key('send')));
      await t.pump();
      expect(draft(t), isEmpty);
      f.chat.sendError = StateError('rejection');
      await t.enterText(find.byKey(const Key('composer')), 'keep this');
      await t.pump();
      await t.tap(find.byKey(const Key('send')));
      await t.pump();
      expect(draft(t), 'keep this');
      f.chat.sendError = null;
      f.chat.sendHold = Completer<void>();
      await t.tap(find.byKey(const Key('send')));
      await t.pump();
      await t.pumpWidget(const SizedBox());
      f.chat.sendHold!.complete();
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'keyboard send shortcut works once and ordinary Enter preserves multiline editing',
    (t) async {
      final f = UiFixture();
      await pumpChat(t, f);
      await t.enterText(find.byKey(const Key('composer')), 'first\nsecond');
      await t.pump();
      await t.testTextInput.receiveAction(TextInputAction.newline);
      await t.pump();
      expect(f.chat.sends, isEmpty);
      expect(draft(t), 'first\nsecond');
      f.chat.sendHold = Completer<void>();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(f.chat.sends, ['first\nsecond']);
      f.chat.sendHold!.complete();
      await t.pump();
    },
  );
  testWidgets(
    'arrivals preserve older reading; an explicit own send returns to bottom',
    (t) async {
      final f = UiFixture();
      for (var i = 0; i < 50; i++) {
        await f.chat.store.add(
          message(
            id: '$i',
            body: 'History message $i with several words to wrap.',
            at: fixtureTime.add(Duration(minutes: i)),
          ),
        );
      }
      await pumpChat(t, f);
      final controller = t
          .widget<ListView>(find.byKey(const Key('messageTimeline')))
          .controller!;
      controller.jumpTo(800);
      await t.pump();
      final viewportTop = t
          .getTopLeft(find.byKey(const Key('messageTimeline')))
          .dy;
      final viewportBottom = t
          .getBottomRight(find.byKey(const Key('messageTimeline')))
          .dy;
      final visible =
          find
                  .byType(MessageBubble)
                  .evaluate()
                  .where((e) {
                    final y = t.getTopLeft(find.byWidget(e.widget)).dy;
                    return y >= viewportTop && y < viewportBottom;
                  })
                  .first
                  .widget
              as MessageBubble;
      final anchorFinder = find.byKey(
        ValueKey('messageBubble-${visible.message.id}'),
      );
      final anchorY = t.getTopLeft(anchorFinder).dy;
      await f.chat.store.add(
        message(
          id: 'arrival',
          body: 'A newer message',
          at: fixtureTime.add(const Duration(hours: 2)),
        ),
      );
      await settleUi(t);
      expect(t.getTopLeft(anchorFinder).dy, closeTo(anchorY, .5));
      expect(find.byKey(const Key('latestMessages')), findsOneWidget);
      f.chat.sendHold = Completer<void>();
      await t.enterText(
        find.byKey(const Key('composer')),
        'reply while reading',
      );
      await t.pump();
      await t.tap(find.byKey(const Key('send')));
      await t.pump();
      f.chat.sendHold!.complete();
      await t.pump();
      await t.pump();
      await t.pumpAndSettle();
      expect(controller.offset, 0);
      expect(find.text('A newer message'), findsOneWidget);
      expect(find.byKey(const Key('latestMessages')), findsNothing);
      await f.chat.store.add(
        message(
          id: 'near',
          body: 'Near-bottom arrival',
          at: fixtureTime.add(const Duration(hours: 3)),
        ),
      );
      await settleUi(t);
      expect(controller.offset, 0);
      expect(find.text('Near-bottom arrival'), findsOneWidget);
    },
  );
  testWidgets(
    'local midnight headings and equal timestamp ordering are stable',
    (t) async {
      final f = UiFixture();
      final midnight = DateTime(2026, 10, 4);
      for (final (id, at) in [
        ('z', midnight),
        ('a', midnight),
        ('previous', midnight.subtract(const Duration(minutes: 1))),
      ]) {
        await f.chat.store.add(message(id: id, body: 'text $id', at: at));
      }
      await pumpChat(t, f);
      expect(find.byType(DaySeparator), findsNWidgets(2));
      expect(
        t.getTopLeft(find.byKey(const ValueKey('a'))).dy,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('z'))).dy),
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('previous'))).dy,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('a'))).dy),
      );
    },
  );
  testWidgets('message selection copies text without sending or leaving chat', (
    t,
  ) async {
    String? copiedText;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': copiedText != null};
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
    final f = UiFixture();
    await f.seed();
    await f.chat.store.add(message(id: 'copy', body: 'Copy this message'));
    await pumpChat(t, f);
    await t.longPress(find.text('Copy this message'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('messageAction-selectText')));
    await t.pumpAndSettle();
    await t.longPress(find.byKey(const Key('selectableMessageText')));
    await t.pumpAndSettle();
    await t.tap(find.text('Select all').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Copy').last);
    await t.pumpAndSettle();
    expect(copiedText, 'Copy this message');
    expect(f.chat.sends, isEmpty);
    expect(find.byType(ChatScreen), findsOneWidget);
  });
  testWidgets(
    'enlarged long-message reading and Latest action fit a narrow viewport',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = UiFixture();
      for (var i = 0; i < 8; i++) {
        await f.chat.store.add(
          message(
            id: 'long-$i',
            body:
                'Message $i: ${List.filled(20, "A longer line of text.").join(" ")}',
            at: fixtureTime.add(Duration(minutes: i)),
          ),
        );
      }
      await pumpChat(t, f, scale: 2);
      final controller = t
          .widget<ListView>(find.byKey(const Key('messageTimeline')))
          .controller!;
      controller.jumpTo(800);
      await t.pump();
      final anchor = find.byKey(const ValueKey('messageBubble-long-7'));
      final y = t.getTopLeft(anchor).dy;
      await f.chat.store.add(
        message(
          id: 'new',
          body: 'An arrival',
          at: fixtureTime.add(const Duration(hours: 1)),
        ),
      );
      await settleUi(t);
      expect(t.getTopLeft(anchor).dy, closeTo(y, .5));
      expect(
        t.getTopLeft(find.byKey(const Key('latestMessages'))).dx,
        greaterThanOrEqualTo(0),
      );
      expect(
        t.getBottomRight(find.byKey(const Key('latestMessages'))).dx,
        lessThanOrEqualTo(320),
      );
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('latestMessages')));
      await t.pumpAndSettle();
      expect(controller.offset, 0);
    },
  );
  for (final size in [
    const Size(320, 640),
    const Size(375, 812),
    const Size(430, 932),
    const Size(768, 1024),
    const Size(812, 375),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('timeline and keyboard layout $size $brightness', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final f = UiFixture();
        await f.seed();
        await f.chat.store.add(
          message(
            id: 'rtl',
            body: 'مرحبا بالعالم 🌿\nA longer message with a second line.',
            outgoing: true,
            at: fixtureTime.add(const Duration(minutes: 1)),
          ),
        );
        await pumpChat(
          t,
          f,
          brightness: brightness,
          scale: 2,
          keyboard: size.height > 600 ? 300 : 0,
        );
        await t.enterText(
          find.byKey(const Key('composer')),
          'First line\nSecond line',
        );
        await t.pump();
        expect(t.takeException(), isNull);
        expect(
          t.getBottomRight(find.byKey(const Key('send'))).dy,
          lessThanOrEqualTo(size.height - (size.height > 600 ? 300 : 0)),
        );
      });
    }
  }
}
