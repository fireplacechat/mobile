// Message requests (issue 248), for review; not part of the byte-identical
// catalog. The chat list with one, three and five waiting; the Requests
// page with a group invitation and requests; the empty page; and narrow
// with large text. Runs on main too, for the before images.
//   TZ=UTC flutter test scripts/render/requests_redesign_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

const _people = ['anna', 'mira', 'oskar', 'ravi'];

void main() {
  setUpAll(loadFonts);
  for (final brightness in Brightness.values) {
    for (final state in [
      'list-1',
      'list-3',
      'list-5',
      'page',
      'empty',
      'page-large',
    ]) {
      testWidgets('${brightness.name} $state', (t) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        final large = state.endsWith('large');
        t.view.physicalSize = Size(large ? 320 : 390, 780);
        t.view.devicePixelRatio = 1;
        t.view.padding = const FakeViewPadding(top: 47);
        addTearDown(t.view.reset);
        final f = UiFixture();
        await f.seed();
        addTearDown(f.session.close);
        final waiting = switch (state) {
          'list-1' || 'empty' => 0,
          'list-3' => 2,
          _ => 4,
        };
        if (state == 'empty') f.hidden = {'alice_theo'};
        f.chat.summaries = [
          ...f.chat.summaries,
          for (var i = 0; i < waiting; i++)
            ChatSummary(
              'alice_${_people[i]}',
              _people[i],
              fixtureTime.subtract(Duration(hours: i + 1)),
              initiator: _people[i],
              accepted: false,
            ),
        ];
        final invitations = state.startsWith('page')
            ? [
                GroupInvitation(
                  gid: 'g1',
                  inviter: 'dana',
                  at: fixtureTime.add(const Duration(minutes: 1)),
                ),
              ]
            : const <GroupInvitation>[];
        final key = GlobalKey();
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              ...f.overrides,
              groupInvitationsProvider.overrideWith(
                (ref) => Stream.value(invitations),
              ),
            ],
            child: RepaintBoundary(
              key: key,
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(large ? 320 : 390, 780),
                  padding: const EdgeInsets.only(top: 47),
                  textScaler: TextScaler.linear(large ? 2 : 1),
                ),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: fireplaceTheme(brightness),
                  home: state.startsWith('list')
                      ? const ChatListScreen()
                      : const RequestsScreen(),
                ),
              ),
            ),
          ),
        );
        await settleUi(t);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('build/requests/${brightness.name}-$state.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(data!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        debugDisableShadows = shadows;
      });
    }
  }
}
