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

  test('a chosen colour is published; a reset publishes the default', () async {
    final (c, f) = await open();
    final appearance = c.read(chatBubbleColorsProvider.notifier);
    await appearance.outgoing(ChatBubbleColor.plum);
    await appearance.reset();
    expect(f.chat.publishedColors, ['plum', 'ember']);
  });

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
