// Choosing a colour puts it on the account's profile (decision 0053), and a
// phone with no choice of its own takes the profile's.
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  Future<(ProviderContainer, UiFixture)> open() async {
    final f = UiFixture();
    await f.seed();
    final c = ProviderContainer(overrides: f.overrides);
    addTearDown(() async {
      c.dispose();
      await f.session.close();
    });
    c.listen(chatBubbleColorsProvider, (_, _) {});
    await c.read(chatBubbleColorsProvider.notifier).loaded;
    return (c, f);
  }

  test('a colour is published once it has been held; trying several '
      'publishes the last', () async {
    ChatAppearance.publishHold = const Duration(milliseconds: 50);
    addTearDown(() => ChatAppearance.publishHold = const Duration(seconds: 10));
    final (c, f) = await open();
    final appearance = c.read(chatBubbleColorsProvider.notifier);
    await appearance.outgoing(ChatBubbleColor.plum);
    await appearance.outgoing(ChatBubbleColor.ocean);
    await appearance.outgoing(ChatBubbleColor.forest);
    expect(f.chat.publishedColors, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(f.chat.publishedColors, ['forest']);
    await appearance.reset();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(f.chat.publishedColors, ['forest', 'ember']);
  }, tags: 'timing');

  test('a phone without a choice takes the profile colour, once', () async {
    final (c, f) = await open();
    final appearance = c.read(chatBubbleColorsProvider.notifier);
    appearance.adopt(ChatBubbleColor.forest);
    expect(c.read(chatBubbleColorsProvider).outgoing, ChatBubbleColor.forest);
    // Taking it is not a choice: nothing is written back.
    expect(f.chat.publishedColors, isEmpty);
    // A colour chosen here stays, whatever the profile says later.
    await appearance.outgoing(ChatBubbleColor.plum);
    appearance.adopt(ChatBubbleColor.ocean);
    expect(c.read(chatBubbleColorsProvider).outgoing, ChatBubbleColor.plum);
  });
}
