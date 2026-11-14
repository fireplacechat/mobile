import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final licenceCatalogProvider = FutureProvider<List<LicenceGroup>>(
  (_) => readLicenceCatalog(LicenseRegistry.licenses),
);

@immutable
class LicenceGroup {
  LicenceGroup({required Iterable<String> packages, required this.text})
    : packages = List.unmodifiable(packages.toSet().toList()..sort()),
      name = _licenceName(text),
      displayText = LicenseEntryWithLineBreaks(
        const [],
        text,
      ).paragraphs.map((paragraph) => paragraph.text).join('\n\n');

  final List<String> packages;
  final String text;
  final String name;
  // Use Flutter's existing paragraph parser to reflow hard-wrapped notices.
  // The exact original is still the grouping key; no words are edited.
  final String displayText;

  bool matchesPackage(String query) {
    final needle = query.trim().toLowerCase();
    return needle.isEmpty ||
        packages.any((package) => package.toLowerCase().contains(needle));
  }
}

/// Retain the exact notice, including copyright lines and original wrapping.
/// A package with multiple notices remains represented in every relevant group.
Future<List<LicenceGroup>> readLicenceCatalog(
  Stream<LicenseEntry> entries,
) async {
  final grouped = <String, Set<String>>{};
  await for (final entry in entries) {
    final text = entry is LicenseEntryWithLineBreaks
        ? entry.text
        : entry.paragraphs.map((paragraph) => paragraph.text).join('\n\n');
    grouped.putIfAbsent(text, () => {}).addAll(entry.packages);
    // Some registry collectors produce all entries together. Yield to input
    // and painting instead of parsing a whole catalogue in one frame.
    await Future<void>.delayed(Duration.zero);
  }
  final result = <LicenceGroup>[];
  for (final entry in grouped.entries) {
    result.add(LicenceGroup(packages: entry.value, text: entry.key));
    await Future<void>.delayed(Duration.zero);
  }
  result.sort((a, b) {
    final name = a.name.compareTo(b.name);
    if (name != 0) return name;
    return a.packages.join(', ').compareTo(b.packages.join(', '));
  });
  return List.unmodifiable(result);
}

String _licenceName(String text) {
  // The registry has no licence-name field. Use an explicit heading when
  // supplied, rather than inferring legal terms from a body or package name.
  final lines = LineSplitter.split(text)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(12)
      .toList();
  final heading = RegExp(
    r'^(?:the )?(?:MIT|BSD|Apache|ISC|Mozilla|GNU|SIL|Eclipse|Boost|Zlib|Unicode|Software)\b.*licen[cs]e\b|^licen[cs]e(?:\s|$)',
    caseSensitive: false,
  );
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.length > 100 || !heading.hasMatch(line)) continue;
    if (line.toLowerCase() == 'apache license' &&
        i + 1 < lines.length &&
        lines[i + 1].startsWith('Version ')) {
      return '$line, ${lines[i + 1]}';
    }
    return line;
  }
  return 'Licence notice';
}
