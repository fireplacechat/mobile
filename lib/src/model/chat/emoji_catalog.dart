import 'package:fireplace/src/model/chat/emoji_catalog_data.dart';

/// One emoji with the words that find it.
class EmojiEntry {
  const EmojiEntry(this.emoji, this.name, this.keywords);
  final String emoji, name;
  final List<String> keywords;
}

class EmojiCategory {
  const EmojiCategory(this.name, this.entries);
  final String name;
  final List<EmojiEntry> entries;
}

/// The bundled emoji, grouped as the picker shows them. Parsed on first use;
/// nothing is fetched and no query leaves the device.
final List<EmojiCategory> emojiCategories = _parse();

List<EmojiCategory> _parse() {
  final categories = <EmojiCategory>[];
  var entries = <EmojiEntry>[];
  for (final line in emojiCatalogData.split('\n')) {
    if (line.isEmpty) continue;
    // The keycap emoji also starts with '#', but its line has tabs.
    if (line.startsWith('#') && !line.contains('	')) {
      entries = <EmojiEntry>[];
      categories.add(EmojiCategory(line.substring(1), entries));
      continue;
    }
    final parts = line.split('\t');
    entries.add(EmojiEntry(parts[0], parts[1], parts.sublist(2)));
  }
  return List.unmodifiable(categories);
}

const emojiSearchLimit = 32;

/// Emoji whose name or keywords match every word typed. An exact name comes
/// first, then names that start with the query, other name matches, and
/// keyword matches.
/// The query is capped and the scan is one pass over a fixed table.
List<EmojiEntry> searchEmoji(String query, {int limit = 120}) {
  final trimmed = query.trim().toLowerCase();
  final words =
      (trimmed.length > emojiSearchLimit
              ? trimmed.substring(0, emojiSearchLimit)
              : trimmed)
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
  if (words.isEmpty) return const [];
  final joined = words.join(' ');
  final exact = <EmojiEntry>[],
      prefix = <EmojiEntry>[],
      named = <EmojiEntry>[],
      tagged = <EmojiEntry>[];
  for (final category in emojiCategories) {
    for (final entry in category.entries) {
      if (entry.name == joined) {
        exact.add(entry);
      } else if (entry.name.startsWith(joined)) {
        prefix.add(entry);
      } else if (words.every(entry.name.contains)) {
        named.add(entry);
      } else if (words.every(
        (word) =>
            entry.name.contains(word) ||
            entry.keywords.any((keyword) => keyword.startsWith(word)),
      )) {
        tagged.add(entry);
      }
    }
  }
  return [...exact, ...prefix, ...named, ...tagged].take(limit).toList();
}
