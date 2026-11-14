import 'package:fireplace/src/model/settings/licence_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/licence_fixture.dart';

class ParagraphNotice extends LicenseEntry {
  const ParagraphNotice();
  @override
  Iterable<String> get packages => ['paragraph_package'];
  @override
  Iterable<LicenseParagraph> get paragraphs => const [
    LicenseParagraph('Custom licence heading', 0),
    LicenseParagraph('Exact custom paragraph.', 1),
  ];
}

void main() {
  test(
    'identical complete notices share one group without losing packages',
    () async {
      final groups = await fixtureLicences();
      expect(groups, hasLength(2));
      final shared = groups.singleWhere(
        (group) => group.text == sharedLicenceText,
      );
      expect(shared.packages, ['example_clock', 'example_parser']);
      expect(shared.name, 'MIT License');
      expect(
        shared.displayText.split(RegExp(r'\s+')),
        shared.text.split(RegExp(r'\s+')),
      );
      expect(shared.matchesPackage('  PARSER '), isTrue);
      expect(shared.matchesPackage('permission'), isFalse);
      expect(shared.matchesPackage(''), isTrue);
    },
  );

  test('different copyright wording and whitespace are not merged', () async {
    final variant = sharedLicenceText.replaceFirst(
      'Example Authors',
      'Other Authors',
    );
    final groups = await readLicenceCatalog(
      Stream.fromIterable([
        const LicenseEntryWithLineBreaks(['a'], sharedLicenceText),
        LicenseEntryWithLineBreaks(['b'], variant),
        LicenseEntryWithLineBreaks([
          'c',
        ], sharedLicenceText.replaceAll('\n', '\r\n')),
      ]),
    );
    expect(groups, hasLength(3));
    expect(
      groups.map((group) => group.text),
      containsAll([
        sharedLicenceText,
        variant,
        sharedLicenceText.replaceAll('\n', '\r\n'),
      ]),
    );
  });

  test(
    'multiple notices per package and repeated package entries are retained',
    () async {
      final groups = await readLicenceCatalog(
        Stream.fromIterable(const [
          LicenseEntryWithLineBreaks(['a', 'b', 'a'], sharedLicenceText),
          LicenseEntryWithLineBreaks(['a'], sharedLicenceText),
          LicenseEntryWithLineBreaks(['a'], otherLicenceText),
        ]),
      );
      expect(groups, hasLength(2));
      expect(
        groups.where((group) => group.packages.contains('a')),
        hasLength(2),
      );
      expect(
        groups.singleWhere((group) => group.name == 'MIT License').packages,
        ['a', 'b'],
      );
    },
  );

  test('paragraph-only entries keep all supplied words', () async {
    final groups = await readLicenceCatalog(
      Stream.value(const ParagraphNotice()),
    );
    expect(groups.single.packages, ['paragraph_package']);
    expect(
      groups.single.text,
      'Custom licence heading\n\nExact custom paragraph.',
    );
    expect(groups.single.name, 'Licence notice');
  });

  test(
    'a failed collector cannot masquerade as a complete catalogue',
    () async {
      Stream<LicenseEntry> failing() async* {
        yield const LicenseEntryWithLineBreaks(['a'], sharedLicenceText);
        throw StateError('collector failed');
      }

      await expectLater(readLicenceCatalog(failing()), throwsStateError);
    },
  );
}
