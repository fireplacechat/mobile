import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'chat_screen_pinning_test.dart' show host;

void main() {
  testWidgets(
    'captured menu reads live chat id after the State receives a new widget',
    (t) async {
      final f = UiFixture();
      await f.seed();
      await host(t, f);
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
      final state = t.state(find.byType(ChatScreen));
      final copy = t
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .first
          .actions
          .firstWhere((a) => a.id == 'copy');
      final overrides = t
          .widget<ProviderScope>(find.byType(ProviderScope))
          .overrides;
      await t.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            navigatorObservers: [chatRouteObserver],
            home: const ChatScreen(chatId: 'alice_unknown'),
          ),
        ),
      );
      await settleUi(t);
      expect(t.state(find.byType(ChatScreen)), same(state));
      copy.onSelected();
      await settleUi(t);
      expect(copied, isNull);
      expect(t.takeException(), isNull);
    },
  );
}
