import 'package:fireplace/src/model/settings/licence_catalog.dart';
import 'package:flutter/foundation.dart';

// Synthetic notices: these are not the application's real legal notices.
const sharedLicenceText =
    'MIT License\n\n'
    'Copyright (c) 2026 Example Authors\n\n'
    'Shared fixture terms for package search and selection tests.\n'
    'Original line breaks and spacing are preserved.\n\n'
    'This is a fictional notice used only in tests and previews.';
const otherLicenceText =
    'Apache License\nVersion 2.0, January 2004\n\n'
    'A separate fictional notice for another example package.';

Future<List<LicenceGroup>> fixtureLicences() => readLicenceCatalog(
  Stream.fromIterable(const [
    LicenseEntryWithLineBreaks(['example_clock'], sharedLicenceText),
    LicenseEntryWithLineBreaks(['example_parser'], sharedLicenceText),
    LicenseEntryWithLineBreaks(['example_transport'], otherLicenceText),
  ]),
);
