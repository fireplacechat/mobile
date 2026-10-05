// REVIEW R07: bubble colours are a temporary, in-memory choice. They must not carry over to the NEXT account
// that signs in on the same phone (provider state otherwise lives until the app is killed).
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/chat_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late StreamController<User?> auth;
  late ProviderContainer c;
  setUp(() {
    auth = StreamController<User?>();
    c = ProviderContainer(
      overrides: [authUserProvider.overrideWith((ref) => auth.stream)],
    );
    c.listen(authUserProvider, (_, _) {});
    c.listen(chatBubbleColorsProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await auth.close();
  });

  test('colours reset when the user signs out', () async {
    auth.add(_User('alice'));
    await settle();
    c.read(chatBubbleColorsProvider.notifier).outgoing(ChatBubbleColor.plum);
    expect(c.read(chatBubbleColorsProvider).outgoing, ChatBubbleColor.plum);
    auth.add(null);
    await settle();
    expect(
      c.read(chatBubbleColorsProvider).outgoing,
      ChatBubbleColor.ember,
      reason: 'back to the default after sign-out',
    );
  });

  test('colours reset when a different account signs in', () async {
    auth.add(_User('alice'));
    await settle();
    c.read(chatBubbleColorsProvider.notifier).incoming(ChatBubbleColor.ocean);
    auth.add(_User('bob'));
    await settle();
    expect(c.read(chatBubbleColorsProvider).incoming, ChatBubbleColor.stone);
  });

  test(
    'colours are kept when the SAME account re-emits (token refresh)',
    () async {
      auth.add(_User('alice'));
      await settle();
      c
          .read(chatBubbleColorsProvider.notifier)
          .outgoing(ChatBubbleColor.forest);
      auth.add(_User('alice'));
      await settle();
      expect(c.read(chatBubbleColorsProvider).outgoing, ChatBubbleColor.forest);
    },
  );
}
