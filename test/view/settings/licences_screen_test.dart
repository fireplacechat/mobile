import 'dart:async';

import 'package:fireplace/src/model/settings/licence_catalog.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/settings/licences_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/licence_fixture.dart';
import '../../support/ui_fixture.dart';

Future<void> pumpLicences(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  double keyboard = 0,
  Future<List<LicenceGroup>> Function()? load,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        licenceCatalogProvider.overrideWith((_) => (load ?? fixtureLicences)()),
      ],
      child: MaterialApp(
        theme: fireplaceTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: const LicencesScreen(),
      ),
    ),
  );
  await settleUi(tester);
}

void main() {
  testWidgets('search filters package names and clearing restores groups', (
    tester,
  ) async {
    await pumpLicences(tester);
    await tester.enterText(find.byKey(const Key('licenceSearch')), 'PARSER');
    await tester.pumpAndSettle();
    expect(find.text('example_clock, example_parser'), findsOneWidget);
    expect(find.text('example_transport'), findsNothing);
    expect(find.byType(Card), findsOneWidget);
    await tester.enterText(find.byKey(const Key('licenceSearch')), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No packages found'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clearLicenceSearch')));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'full notice unchanged and selectable, narrow large $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpLicences(tester, brightness: brightness, scale: 2);
        await tester.enterText(find.byKey(const Key('licenceSearch')), 'clock');
        await tester.pumpAndSettle();
        final card = find.byType(Card);
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(find.byType(LicenceDetailScreen), findsOneWidget);
        expect(
          tester
              .widget<SelectableText>(find.byKey(const Key('fullLicenceText')))
              .data,
          (await tester.runAsync(fixtureLicences))!
              .singleWhere((group) => group.name == 'MIT License')
              .displayText,
        );
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('licenceSearch')))
              .controller!
              .text,
          'clock',
        );
      },
    );
  }

  testWidgets('short keyboard viewport remains scroll reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpLicences(tester, scale: 2, keyboard: 200);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('licenceSearch')));
    await tester.enterText(find.byKey(const Key('licenceSearch')), 'parser');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('collector errors show a plain retry and recover', (
    tester,
  ) async {
    var attempts = 0;
    await pumpLicences(
      tester,
      load: () async {
        if (attempts++ == 0) throw StateError('private implementation detail');
        return fixtureLicences();
      },
    );
    expect(find.text('Could not load licences'), findsOneWidget);
    expect(find.textContaining('private implementation'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));
  });

  testWidgets('leaving during loading does not update a disposed screen', (
    tester,
  ) async {
    final pending = Completer<List<LicenceGroup>>();
    await pumpLicences(tester, load: () => pending.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete((await tester.runAsync(fixtureLicences))!);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
