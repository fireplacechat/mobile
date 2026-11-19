// Renders the app from its sign-in gate with no recovery key yet, into
// build/renders/backup-notice/: the chat list, a conversation and Settings.
// The reminder shows on the chat list only (issue 201).
//
//   TZ=UTC flutter test scripts/render/render_backup_notice_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

class _User extends Fake implements User {
  @override
  String get uid => 'alice';
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('no recovery key yet, ${brightness.name}', (t) async {
      await t.runAsync(loadFonts);
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final fixture = UiFixture(overrideAuth: false);
      await fixture.seed();
      addTearDown(fixture.session.close);
      final boundary = GlobalKey();
      final theme = fireplaceTheme(brightness);
      await t.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...fixture.overrides,
            authUserProvider.overrideWith((ref) => Stream.value(_User())),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
              ),
              home: const AuthGate(),
            ),
          ),
        ),
      );
      await settleUi(t);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();

      Future<void> capture(String name) async {
        final renderer =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
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
        File('build/renders/backup-notice/${brightness.name}-$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!);
      }

      await capture('chat-list');
      await t.tap(find.byKey(const ValueKey('conversation-alice_fred')));
      await t.pumpAndSettle();
      await capture('conversation');
      await t.tap(find.byKey(const Key('chatBack')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings')));
      await t.pumpAndSettle();
      await capture('settings');
      await t.pumpWidget(const SizedBox());
      debugDisableShadows = previousShadows;
    });
  }
}
