import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_drafts.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  late UiFixture fixture;
  late ProviderContainer container;
  late ChatDrafts drafts;

  setUp(() {
    fixture = UiFixture();
    container = ProviderContainer(overrides: fixture.overrides);
    drafts = container.read(chatDraftsProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await fixture.session.close();
  });

  test('drafts reset on sign-out and reject stale account writes', () {
    drafts.save('alice_fred', 'Private draft', ownerUid: 'alice');
    expect(drafts.textFor('alice_fred', ownerUid: 'alice'), 'Private draft');
    expect(drafts.textFor('alice_fred', ownerUid: 'bob'), isEmpty);
    drafts.save('alice_fred', 'Wrong account', ownerUid: 'bob');
    expect(drafts.textFor('alice_fred', ownerUid: 'alice'), 'Private draft');
    container.updateOverrides([
      ...fixture.overrides.skip(1),
      appSessionProvider.overrideWithValue(const AsyncData(null)),
    ]);
    expect(container.read(chatDraftsProvider), isEmpty);
    drafts.save('alice_fred', 'Late edit', ownerUid: 'alice');
    expect(container.read(chatDraftsProvider), isEmpty);
    container.updateOverrides(fixture.overrides);
    expect(container.read(chatDraftsProvider), isEmpty);
  });

  test('draft memory is bounded by conversations and Unicode characters', () {
    for (var i = 0; i < maxChatDrafts; i++) {
      drafts.save('chat-$i', 'Draft $i', ownerUid: 'alice');
    }
    drafts.save('chat-0', 'Recently edited', ownerUid: 'alice');
    drafts.save('new-chat', 'New draft', ownerUid: 'alice');
    expect(container.read(chatDraftsProvider), hasLength(maxChatDrafts));
    expect(drafts.textFor('chat-0', ownerUid: 'alice'), 'Recently edited');
    expect(drafts.textFor('chat-1', ownerUid: 'alice'), isEmpty);
    drafts.save(
      'new-chat',
      '😀' * (maxMessageCharacters + 1),
      ownerUid: 'alice',
    );
    final saved = drafts.textFor('new-chat', ownerUid: 'alice');
    expect(messageCharacters(saved), maxMessageCharacters);
    expect(saved, '😀' * maxMessageCharacters);
    drafts.save('new-chat', '', ownerUid: 'alice');
    expect(container.read(chatDraftsProvider).containsKey('new-chat'), isFalse);
  });
}
