// Renders the Invite friends page into build/renders/invites/, for review and
// for pull requests:
//
//   TZ=UTC flutter test scripts/render/render_invites_test.dart
//
// Three rows as a new account sees them: one ready, two counting down. A fake
// Firestore and a fixed clock, so the images are the same on every run.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/invite_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/invites/invite_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  final created = DateTime.utc(2026, 11, 14, 12);

  for (final brightness in Brightness.values) {
    testWidgets('invite tickets, ${brightness.name}', (t) async {
      await t.runAsync(loadFonts);
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final db = FakeFirebaseFirestore();
      final fixture = UiFixture();
      await fixture.seed();
      addTearDown(fixture.session.close);
      await t.runAsync(
        () => db.doc('users/alice').set({
          'username': 'alice',
          'createdAt': Timestamp.fromDate(created),
        }),
      );
      final boundary = GlobalKey();
      final theme = fireplaceTheme(brightness);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            ...fixture.overrides,
            firestoreProvider.overrideWithValue(db),
            // An hour after sign-up: the first invite is ready.
            inviteClockProvider.overrideWithValue(
              () => created.add(const Duration(hours: 1)),
            ),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
              ),
              home: const InviteScreen(),
            ),
          ),
        ),
      );
      await settleUi(t);
      final renderer =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await t.runAsync(() async {
        final image = await renderer.toImage(pixelRatio: 2);
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      });
      File('build/renders/invites/${brightness.name}-invite-tickets.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!);
      // The test binding checks this is back before the body ends.
      debugDisableShadows = previousShadows;
    });
  }
}
