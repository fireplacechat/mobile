import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/model/chat/emoji_catalog.dart';
import 'package:fireplace/src/view/chat/message_reactions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the catalog has the eight picker categories, in order', () {
    expect(emojiCategories.map((c) => c.name), [
      'Smileys & People',
      'Animals & Nature',
      'Food & Drink',
      'Activities',
      'Travel & Places',
      'Objects',
      'Symbols',
      'Flags',
    ]);
    expect(emojiCategories.first.entries.first.emoji, '😀');
    expect(emojiCategories.every((c) => c.entries.length > 50), isTrue);
  });

  test('every emoji is one the encrypted reaction format accepts', () {
    // The picker must never offer something a peer would reject, and the
    // reaction format itself is unchanged.
    final all = [for (final c in emojiCategories) ...c.entries];
    expect(all.length, greaterThan(1500));
    expect(all.where((e) => !validReactionEmoji(e.emoji)), isEmpty);
    expect(all.map((e) => e.emoji).toSet().length, all.length);
    expect(all.where((e) => e.name.contains('skin tone')), isEmpty);
    expect(all.where((e) => e.name.isEmpty), isEmpty);
  });

  test('the quick reactions are all in the catalog', () {
    final all = {
      for (final c in emojiCategories)
        for (final e in c.entries) e.emoji,
    };
    expect(quickReactions.where((e) => !all.contains(e)), isEmpty);
  });

  test('the keycap that starts with # is an emoji, not a category', () {
    final symbols = emojiCategories.firstWhere((c) => c.name == 'Symbols');
    expect(symbols.entries.any((e) => e.emoji.startsWith('#')), isTrue);
  });

  group('searchEmoji', () {
    List<String> find(String query) =>
        searchEmoji(query).map((e) => e.emoji).toList();

    test('puts an exact name, then names starting with the query, first', () {
      // "fire" itself, then "firefighter", which only starts with it.
      expect(find('fire').take(2), ['🔥', '🧑‍🚒']);
      expect(find('red heart').first, '❤️');
      expect(find('thumbs up').first, '👍');
      expect(find('fire').first, '🔥');
    });
    test('matches every word in any order, ignoring case and spaces', () {
      expect(find('  HEART red '), contains('❤️'));
      expect(find('face tears joy'), contains('😂'));
    });
    test('matches keywords as well as names', () {
      // "hundred" is a keyword of the 💯 emoji, not part of its name.
      expect(find('hundred'), contains('💯'));
      expect(find('laugh'), contains('😂'));
    });
    test('returns nothing for blank or unknown text', () {
      expect(find(''), isEmpty);
      expect(find('   '), isEmpty);
      expect(find('zzzzqqqq'), isEmpty);
    });
    test('is bounded for long input and broad matches', () {
      expect(searchEmoji('a').length, lessThanOrEqualTo(120));
      expect(searchEmoji('face', limit: 5).length, 5);
      final long = 'heart ${'x' * 5000}';
      final watch = Stopwatch()..start();
      expect(searchEmoji(long), isA<List<EmojiEntry>>());
      // Not a speed threshold: only that the cap keeps this from scaling
      // with the input.
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    }, tags: 'timing');
  });
}
