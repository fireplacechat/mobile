// Offline catalog of the real widgets. Run with TZ=UTC for repeatable dates.
// flutter test scripts/render/render_screens_test.dart
// PNGs and a state manifest are written to build/renders/, never shipped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/view/account/account_deletion_screens.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/chat/chat_details_screen.dart';
import 'package:fireplace/src/ui/chat_list_screen.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/search/message_search_results.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/view/notifications/in_app_notice.dart';
import 'package:fireplace/src/view/settings/chat_appearance.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/view/chat/widgets/message_bubble.dart';
import 'package:fireplace/src/view/devices/devices_screen.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/ui/new_device_screen.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';
import 'package:fireplace/src/view/recovery/recovery_key_screen.dart';
import 'package:fireplace/src/view/devices/link_new_device_screen.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:fireplace/src/view/safety/blocked_users_screen.dart';
import 'package:fireplace/src/ui/settings_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import '../../test/support/account_fixture.dart';

Future<void> loadFonts() async {
  final config = File('.dart_tool/package_config.json');
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final flutter = packages.cast<Map>().firstWhere(
    (p) => p['name'] == 'flutter',
  );
  final root = Directory.fromUri(
    config.uri.resolve(flutter['rootUri'] as String),
  ).parent.parent;
  final fonts = Directory('${root.path}/bin/cache/artifacts/material_fonts');
  final roboto = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
  ]) {
    final file = File('${fonts.path}/$name');
    if (file.existsSync()) {
      roboto.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
  }
  await roboto.load();
  // Flutter widget tests otherwise use Ahem blocks for the platform monospace
  // alias. This SDK-font stand-in is preview-only, not a shipping font change.
  await (FontLoader('monospace')..addFont(
        Future.value(
          ByteData.sublistView(
            File('${fonts.path}/Roboto-Bold.ttf').readAsBytesSync(),
          ),
        ),
      ))
      .load();
  await (FontLoader('MaterialIcons')..addFont(
        Future.value(
          ByteData.sublistView(
            File('${fonts.path}/MaterialIcons-Regular.otf').readAsBytesSync(),
          ),
        ),
      ))
      .load();
}

enum CatalogInteraction { searchEmpty, compose, sending }

class CatalogCase {
  const CatalogCase(
    this.name,
    this.screen, {
    this.overrides = const [],
    this.signup = false,
    this.interaction,
    this.size = const Size(390, 844),
    this.textScale = 1,
    this.keyboardInset = 0,
    this.prepare,
    this.services,
    this.act,
    this.overrideAuth = true,
    this.notices = false,
  });
  final void Function(UiFixture)? prepare;
  final List<Override> Function(UiFixture)? services;
  final Future<void> Function(WidgetTester, UiFixture)? act;
  final String name;
  final Widget screen;
  final List<Override> overrides;
  final bool signup, overrideAuth, notices;
  final CatalogInteraction? interaction;
  final Size size;
  final double textScale, keyboardInset;
}

void main() {
  final manifest = <Map<String, Object>>[];
  setUpAll(loadFonts);
  tearDownAll(() {
    File(
      'build/renders/manifest.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  });
  final cases = [
    for (final mine in [false, true])
      CatalogCase(
        mine ? 'message-actions-outgoing' : 'message-actions-incoming',
        const ChatScreen(chatId: 'alice_fred'),
        act: (t, f) async {
          final target = find.byKey(
            ValueKey('messageBubble-${mine ? '4' : '5'}'),
          );
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await t.longPress(target);
          await t.pumpAndSettle();
        },
      ),
    CatalogCase(
      'message-actions-narrow-large',
      const ChatScreen(chatId: 'alice_fred'),
      size: const Size(320, 640),
      textScale: 2,
      act: (t, f) async {
        await t.longPress(find.byKey(const ValueKey('messageBubble-5')));
        await t.pumpAndSettle();
      },
    ),
    CatalogCase(
      'message-report',
      const ChatScreen(chatId: 'alice_fred'),
      act: (t, f) async {
        await t.longPress(find.byKey(const ValueKey('messageBubble-5')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('messageAction-report')));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('reportInclude')));
        await t.pumpAndSettle();
      },
    ),
    for (final keyboard in [false, true])
      CatalogCase(
        keyboard ? 'select-message-text-keyboard' : 'select-message-text',
        const ChatScreen(chatId: 'alice_fred'),
        size: keyboard ? const Size(320, 640) : const Size(390, 844),
        textScale: keyboard ? 2 : 1,
        keyboardInset: keyboard ? 220 : 0,
        act: (t, f) async {
          await t.longPress(find.byKey(const ValueKey('messageBubble-5')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('messageAction-selectText')));
          await t.pumpAndSettle();
        },
      ),
    CatalogCase(
      'oversized-message',
      const ChatScreen(chatId: 'alice_fred'),
      prepare: (f) => unawaited(
        f.chat.store.add(
          message(
            id: 'oversize-example',
            body: '**Literal from another client** ${'x' * 17000}',
            at: fixtureTime.add(const Duration(minutes: 1)),
          ),
        ),
      ),
    ),
    for (final landscape in [false, true])
      CatalogCase(
        landscape
            ? 'composer-limit-landscape-keyboard'
            : 'composer-limit-narrow-large',
        const ChatScreen(chatId: 'alice_fred'),
        size: landscape ? const Size(812, 375) : const Size(320, 640),
        textScale: 2,
        keyboardInset: landscape ? 140 : 220,
        act: (t, f) async {
          await t.enterText(find.byKey(const Key('composer')), 'a' * 16384);
          await t.pump();
        },
      ),
    CatalogCase(
      'composer-near-limit',
      const ChatScreen(chatId: 'alice_fred'),
      act: (t, f) async {
        await t.enterText(find.byKey(const Key('composer')), 'a' * 16380);
        await t.pump();
      },
    ),
    CatalogCase(
      'formatted-message',
      const ChatScreen(chatId: 'alice_fred'),
      prepare: (f) => unawaited(
        f.chat.store.add(
          message(
            id: 'format-example',
            body: '**Saturday** sounds good. _Around two?_ ~~Three~~ ☕',
            at: fixtureTime.add(const Duration(minutes: 1)),
          ),
        ),
      ),
    ),
    CatalogCase(
      'chat-list-muted',
      const ChatListScreen(),
      act: (t, f) async {
        await f.session.chatPreferences.mute('alice_fred', true);
        await settleUi(t);
      },
    ),
    CatalogCase('chat-back-unread', const ChatScreen(chatId: 'alice_bob')),
    CatalogCase(
      'forward-message',
      ForwardMessageScreen(
        message: message(
          id: 'source',
          body: '**See you at two.**',
          outgoing: true,
        ),
      ),
      act: (t, f) async {
        await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
        await t.pump();
      },
    ),
    CatalogCase(
      'global-message-search',
      const ChatListScreen(),
      act: (t, f) async {
        await t.enterText(find.byKey(const Key('chatSearch')), 'Saturday');
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        final c = ProviderScope.containerOf(
          t.element(find.byType(ChatListScreen)),
        );
        for (
          var attempt = 0;
          attempt < 30 && !c.read(messageSearchProvider('saturday')).hasValue;
          attempt++
        ) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await t.pump(const Duration(milliseconds: 30));
        }
        expect(c.read(messageSearchProvider('saturday')).hasValue, isTrue);
        await settleUi(t);
      },
    ),
    const CatalogCase(
      'search-message-location',
      ChatScreen(chatId: 'alice_fred', initialMessageId: '1'),
    ),
    for (final showText in [false, true])
      CatalogCase(
        showText ? 'notification-preview' : 'notification-no-preview',
        const ChatListScreen(),
        notices: true,
        act: (t, f) async {
          await f.session.chatPreferences.previews(showText);
          await f.chat.store.add(
            message(
              id: 'notification-fixture',
              body: 'See you in the garden ☕',
              at: fixtureTime.add(const Duration(minutes: 1)),
            ),
          );
          await settleUi(t);
        },
      ),
    const CatalogCase(
      'link-device-narrow-large',
      LinkNewDeviceScreen(),
      size: Size(320, 640),
      textScale: 2,
    ),
    const CatalogCase(
      'link-device-landscape',
      LinkNewDeviceScreen(),
      size: Size(812, 375),
    ),
    const CatalogCase('privacy-and-terms', LegalLinksScreen()),
    CatalogCase(
      'blocked-people',
      const BlockedUsersScreen(),
      prepare: (f) => f.blocked = {'fred', 'bob'},
    ),
    const CatalogCase('blocked-people-empty', BlockedUsersScreen()),
    CatalogCase(
      'verification-verified',
      const VerifyScreen(peerUid: 'fred', peerName: 'fred'),
      prepare: (f) => f.verified = true,
    ),
    CatalogCase(
      'identity-held',
      const ChatScreen(chatId: 'alice_fred'),
      prepare: (f) {
        f.alerts = {'fred': List.filled(64, 9)};
        f.freshDevices = ['example-second-device'];
      },
    ),
    CatalogCase(
      'conversation-blocked',
      const ChatScreen(chatId: 'alice_fred'),
      prepare: (f) => f.blocked = {'fred'},
    ),
    CatalogCase(
      'request-allowance-reached',
      const ChatScreen(chatId: 'alice_fred'),
      prepare: (f) {
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
      },
    ),
    for (final outcome in [
      SendOutcome.publishUnknown,
      SendOutcome.publishedLocalSaveFailed,
    ])
      CatalogCase(
        outcome == SendOutcome.publishUnknown
            ? 'message-not-confirmed'
            : 'sent-local-save-failed',
        const ChatScreen(chatId: 'alice_fred'),
        prepare: (f) {
          f.chat.sendError = SendNotConfirmedException(
            outcome: outcome,
            chatId: 'alice_fred',
            messageId: 'example-pending',
            body: 'See you at two.',
            attemptedAt: fixtureTime,
            persisted: false,
          );
        },
        act: (t, f) async {
          await t.enterText(
            find.byKey(const Key('composer')),
            'See you at two.',
          );
          await t.pump();
          await t.tap(find.byKey(const Key('send')));
          await settleUi(t);
        },
      ),
    CatalogCase(
      'report-dialog',
      ChatDetailsScreen(
        peerUid: 'fred',
        chatId: 'alice_fred',
        name: 'fred',
        onBlock: () async {},
        onUnblock: () async {},
      ),
      act: (t, f) async {
        await t.tap(find.byKey(const Key('detailsReport')));
        await t.pump(const Duration(milliseconds: 350));
        await settleUi(t);
      },
    ),
    CatalogCase(
      'password-dialog',
      const SettingsScreen(),
      services: (f) => [authServiceProvider.overrideWithValue(ActionAuth())],
      act: (t, f) async {
        await t.ensureVisible(find.byKey(const Key('changePassword')));
        await t.tap(find.byKey(const Key('changePassword')));
        await t.pump(const Duration(milliseconds: 350));
        await settleUi(t);
      },
    ),
    CatalogCase(
      'recovery-example-key',
      const RecoveryKeyScreen(),
      services: (f) => [
        recoveryServiceProvider.overrideWithValue(ActionRecovery()),
      ],
      act: (t, f) async {
        await t.tap(find.byKey(const Key('createRecovery')));
        await settleUi(t);
      },
    ),
    CatalogCase(
      'recovery-replace-confirmation',
      const RecoveryKeyScreen(),
      prepare: (f) => f.hasBackup = true,
      services: (f) => [
        recoveryServiceProvider.overrideWithValue(ActionRecovery()),
      ],
      act: (t, f) async {
        await t.tap(find.byKey(const Key('createRecovery')));
        await t.pump(const Duration(milliseconds: 350));
        await settleUi(t);
      },
    ),
    CatalogCase(
      'link-approval-code',
      LinkNewDeviceScreen(
        scanCode: (_) async => 'example-invalid-qr-only-fake-service',
      ),
      services: (f) => [
        recoveryServiceProvider.overrideWithValue(ActionRecovery()),
      ],
      act: (t, f) async {
        await t.scrollUntilVisible(
          find.byKey(const Key('scanLink')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.byKey(const Key('scanLink')));
        await settleUi(t);
      },
    ),

    const CatalogCase('chat-colors', ChatAppearanceScreen()),
    CatalogCase(
      'components',
      Scaffold(
        appBar: AppBar(title: const Text('Components')),
        body: UiPageScroll(
          children: [
            const Center(child: PersonAvatar(name: 'Fred')),
            const SizedBox(height: 16),
            Builder(
              builder: (context) => Text(
                'A little closer',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 16),
            const TextField(decoration: InputDecoration(labelText: 'Username')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Continue')),
                OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
              ],
            ),
            const UiNotice(
              text: 'Review this contact’s security code.',
              warning: true,
            ),
            MessageBubble(
              message: message(id: 'preview-in', body: 'See you on Saturday ☕'),
            ),
            MessageBubble(
              message: message(
                id: 'preview-out',
                body: 'Looking forward to it.',
                outgoing: true,
              ),
            ),
          ],
        ),
      ),
    ),
    const CatalogCase(
      'chat-list-narrow-large',
      ChatListScreen(),
      size: Size(320, 640),
      textScale: 2,
    ),
    const CatalogCase(
      'chat-narrow-keyboard',
      ChatScreen(chatId: 'alice_fred'),
      size: Size(320, 640),
      textScale: 2,
      keyboardInset: 300,
    ),
    const CatalogCase(
      'chat-landscape-large',
      ChatScreen(chatId: 'alice_fred'),
      size: Size(812, 375),
      textScale: 2,
    ),
    const CatalogCase(
      'chat-list-search-empty',
      ChatListScreen(),
      interaction: CatalogInteraction.searchEmpty,
    ),
    const CatalogCase(
      'conversation-composing',
      ChatScreen(chatId: 'alice_fred'),
      interaction: CatalogInteraction.compose,
    ),
    const CatalogCase(
      'conversation-sending',
      ChatScreen(chatId: 'alice_fred'),
      interaction: CatalogInteraction.sending,
    ),
    const CatalogCase('chat-list', ChatListScreen()),
    CatalogCase(
      'chat-list-empty',
      const ChatListScreen(),
      overrides: [chatsProvider.overrideWith((ref) => Stream.value([]))],
    ),
    CatalogCase(
      'chat-list-loading',
      const ChatListScreen(),
      overrides: [chatsProvider.overrideWith((ref) => const Stream.empty())],
    ),
    CatalogCase(
      'chat-list-error',
      const ChatListScreen(),
      overrides: [
        chatsProvider.overrideWith(
          (ref) => Stream.error(StateError('fixture')),
        ),
      ],
    ),
    const CatalogCase('conversation', ChatScreen(chatId: 'alice_fred')),
    CatalogCase(
      'conversation-empty',
      const ChatScreen(chatId: 'alice_fred'),
      overrides: [
        messagesProvider('alice_fred').overrideWith((ref) => Stream.value([])),
      ],
    ),
    CatalogCase(
      'conversation-error',
      const ChatScreen(chatId: 'alice_fred'),
      overrides: [
        messagesProvider('alice_fred')
            .overrideWith((ref) => Stream.error(StateError('fixture'))),
      ],
    ),
    const CatalogCase('message-request', ChatScreen(chatId: 'alice_theo')),
    const CatalogCase('requests', RequestsScreen()),
    CatalogCase(
      'chat-details',
      ChatDetailsScreen(
        peerUid: 'fred',
        chatId: 'alice_fred',
        name: 'fred',
        onBlock: () async {},
        onUnblock: () async {},
      ),
    ),
    const CatalogCase(
      'verification',
      VerifyScreen(peerUid: 'fred', peerName: 'fred'),
    ),
    const CatalogCase('settings', SettingsScreen()),
    const CatalogCase('devices', DevicesScreen()),
    const CatalogCase('recovery', RecoveryKeyScreen()),
    const CatalogCase('link-device', LinkNewDeviceScreen()),
    const CatalogCase('new-device', NewDeviceScreen(uid: 'alice')),
    const CatalogCase('delete-account', DeleteAccountScreen()),
    const CatalogCase('deletion-resume', DeleteAccountScreen(resume: true)),
    const CatalogCase('sign-in', AuthScreen()),
    const CatalogCase('sign-up', AuthScreen(), signup: true),
    const CatalogCase(
      'sign-up-narrow-large',
      AuthScreen(),
      signup: true,
      size: Size(320, 640),
      textScale: 2,
    ),
    const CatalogCase(
      'loading-landscape-large',
      FireplaceSplash(message: 'Preparing your account…'),
      size: Size(812, 375),
      textScale: 2,
    ),
    const CatalogCase(
      'loading',
      FireplaceSplash(message: 'Preparing your account…'),
    ),
    CatalogCase(
      'auth-error',
      const AuthGate(),
      overrideAuth: false,
      overrides: [
        authUserProvider.overrideWith(
          (ref) => Stream.error(StateError('fixture')),
        ),
      ],
    ),
  ];
  for (final brightness in Brightness.values) {
    final theme = brightness.name;
    for (final spec in cases) {
      testWidgets('${spec.name} $theme', (tester) async {
        // The widget-test default turns blurred card shadows into hard black
        // outlines. This catalog previews the app's actual painted surfaces.
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        tester.view.physicalSize = spec.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = UiFixture(overrideAuth: spec.overrideAuth);
        await fixture.seed();
        spec.prepare?.call(fixture);
        addTearDown(fixture.session.close);
        final boundary = GlobalKey();
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...fixture.overrides,
              ...spec.overrides,
              ...?spec.services?.call(fixture),
            ],
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                navigatorKey: navigatorKey,
                navigatorObservers: [chatRouteObserver],
                debugShowCheckedModeBanner: false,
                theme: fireplaceTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(spec.textScale),
                    viewInsets: EdgeInsets.only(bottom: spec.keyboardInset),
                  ),
                  child: spec.notices
                      ? InAppNoticeHost(
                          navigatorKey: navigatorKey,
                          child: child!,
                        )
                      : child!,
                ),
                home: spec.screen,
              ),
            ),
          ),
        );
        await settleUi(tester);
        if (spec.signup) {
          await tester.ensureVisible(find.byKey(const Key('toggle')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('toggle')));
          await settleUi(tester);
        }
        if (spec.interaction == CatalogInteraction.searchEmpty) {
          await tester.enterText(find.byKey(const Key('chatSearch')), 'nobody');
          await settleUi(tester);
        } else if (spec.interaction != null) {
          await tester.enterText(
            find.byKey(const Key('composer')),
            'See you at two.\nI will bring dessert.',
          );
          await tester.pump();
          if (spec.interaction == CatalogInteraction.sending) {
            fixture.chat.sendHold = Completer<void>();
            await tester.tap(find.byKey(const Key('send')));
            await settleUi(tester);
          }
        }
        await spec.act?.call(tester, fixture);
        expect(
          tester.takeException(),
          isNull,
          reason: '${spec.name}: no render overflow or uncaught error',
        );
        // Advance every fixture by the same time so loading indicators are repeatable too.
        await tester.pump(const Duration(milliseconds: 400));
        final renderer =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final png = await tester.runAsync(() async {
          final image = await renderer.toImage(pixelRatio: 2);
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
          }
        });
        final filename = '$theme-${spec.name}.png';
        File('build/renders/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!);
        manifest.add({
          'screen': spec.name,
          'theme': theme,
          'file': filename,
          'width': spec.size.width,
          'height': spec.size.height,
          'textScale': spec.textScale,
          'keyboardInset': spec.keyboardInset,
          'fixture': 'fictional/in-memory',
          'time': fixtureTime.toIso8601String(),
        });
        await tester.pumpWidget(const SizedBox());
        fixture.chat.sendHold?.complete();
        await tester.pump();
        // Flutter checks painting invariants before running tearDown callbacks.
        debugDisableShadows = previousShadows;
      });
    }
  }
}
