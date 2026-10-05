import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/ui/account_deletion_screens.dart';
import 'package:fireplace/src/ui/auth_screen.dart';
import 'package:fireplace/src/ui/chat_appearance.dart';
import 'package:fireplace/src/ui/chat_list_screen.dart';
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/ui/devices_screen.dart';
import 'package:fireplace/src/ui/new_device_screen.dart';
import 'package:fireplace/src/ui/legal_links.dart';
import 'package:fireplace/src/ui/recovery_screens.dart';
import 'package:fireplace/src/ui/safety_ui.dart';
import 'package:fireplace/src/ui/settings_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:fireplace/src/ui/verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/render/render_screens_test.dart' show loadFonts;
import '../support/ui_fixture.dart';

const sizes = [
  Size(320, 640),
  Size(375, 812),
  Size(430, 932),
  Size(768, 1024),
  Size(812, 375),
];
Future<void> pump(
  WidgetTester t,
  UiFixture f,
  Widget screen,
  Brightness brightness,
  double scale,
  double keyboard,
) async {
  await t.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await settleUi(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  for (final size in sizes) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('screen matrix $size $brightness scale $scale', (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final screens = <(String, Widget, bool)>[
            ('settings', const SettingsScreen(), false),
            ('legal', const LegalLinksScreen(), false),
            ('devices', const DevicesScreen(), false),
            ('recovery', const RecoveryKeyScreen(), false),
            ('link', const LinkNewDeviceScreen(), false),
            ('setup', const NewDeviceScreen(uid: 'alice'), false),
            ('restore', const RecoveryEntryScreen(uid: 'alice'), true),
            (
              'verification',
              const VerifyScreen(
                peerUid: 'fred',
                peerName: 'long_username_here',
              ),
              false,
            ),
            ('requests', const RequestsScreen(), false),
            ('delete', const DeleteAccountScreen(), true),
            ('auth', const AuthScreen(), true),
            ('list', const ChatListScreen(), true),
            ('colors', const ChatAppearanceScreen(), false),
            for (final mode in [
              'chat',
              'incoming',
              'held',
              'blocked',
              'unconfirmed',
              'capped',
            ])
              (mode, const ChatScreen(chatId: 'alice_fred'), mode == 'chat'),
          ];
          for (final (name, screen, input) in screens) {
            for (final keyboard in input ? [0.0, 300.0] : [0.0]) {
              final f = UiFixture();
              await f.seed();
              f.names['fred'] = Future.value('long_username_here');
              if (name == 'incoming') {
                f.chat.summaries = [
                  ChatSummary(
                    'alice_fred',
                    'fred',
                    fixtureTime,
                    accepted: false,
                    initiator: 'fred',
                  ),
                ];
              }
              if (name == 'capped') {
                f.chat.summaries = [
                  ChatSummary(
                    'alice_fred',
                    'fred',
                    fixtureTime,
                    accepted: false,
                    initiator: 'alice',
                    requestCount: 3,
                  ),
                ];
              }
              if (name == 'blocked') f.blocked = {'fred'};
              if (name == 'held') {
                f.alerts = {'fred': List.filled(64, 9)};
                f.freshDevices = ['example'];
              }
              if (name == 'unconfirmed') {
                await f.chat.store.add(
                  message(
                    id: 'pending',
                    body: 'An uncertain message',
                    outgoing: true,
                    at: fixtureTime.add(const Duration(minutes: 1)),
                    status: MessageStatus.unconfirmed,
                  ),
                );
              }
              await pump(t, f, screen, brightness, scale, keyboard);
              expect(
                t.takeException(),
                isNull,
                reason:
                    '$name keyboard $keyboard $size $brightness scale $scale',
              );
              await t.pumpWidget(const SizedBox());
              await t.runAsync(f.session.close);
            }
          }
        });
      }
    }
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      '3x signup and safety dialog actions remain reachable $brightness',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final f = UiFixture();
        addTearDown(f.session.close);
        await pump(t, f, const AuthScreen(), brightness, 3, 300);
        await t.ensureVisible(find.byKey(const Key('toggle')));
        await t.pump();
        await t.tap(find.byKey(const Key('toggle')));
        await settleUi(t);
        await t.ensureVisible(find.byKey(const Key('age16')));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(
          t.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
          isNull,
        );
        await pump(
          t,
          f,
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => confirmBlock(context, 'long_username_here'),
                  child: const Text('Block'),
                ),
              ),
            ),
          ),
          brightness,
          3,
          300,
        );
        await t.tap(find.text('Block'));
        await t.pump(const Duration(milliseconds: 350));
        await t.ensureVisible(find.byKey(const Key('confirmBlock')));
        await t.pump();
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('confirmBlock')));
        await t.pumpAndSettle();
        expect(find.textContaining('Block @'), findsNothing);
      },
    );
    for (final screen in ['list', 'settings', 'colors']) {
      testWidgets('tap labels, targets and text contrast $screen $brightness', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        try {
          t.view.physicalSize = const Size(430, 932);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final f = UiFixture();
          await f.seed();
          addTearDown(f.session.close);
          await pump(
            t,
            f,
            screen == 'list'
                ? const ChatListScreen()
                : screen == 'settings'
                ? const SettingsScreen()
                : const ChatAppearanceScreen(),
            brightness,
            1,
            0,
          );
          await t.pump(const Duration(milliseconds: 400));
          await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(t, meetsGuideline(androidTapTargetGuideline));
          await expectLater(t, meetsGuideline(textContrastGuideline));
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
