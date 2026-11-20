// Settings is a main page of categories, each opening its own page (issue
// 249). Every setting is reachable from the category the issue names, Back
// returns to the main page, and failures still show plainly.
import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/wrapping_secret_store.dart';
import 'package:fireplace/src/model/account/takeover.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/settings/account_settings_screen.dart';
import 'package:fireplace/src/view/settings/appearance_settings_screen.dart';
import 'package:fireplace/src/view/settings/devices_settings_screen.dart';
import 'package:fireplace/src/view/settings/help_settings_screen.dart';
import 'package:fireplace/src/view/settings/notification_settings_screen.dart';
import 'package:fireplace/src/view/settings/privacy_settings_screen.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/widgets/settings/settings_icon.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';
import 'package:fireplace/src/widgets/swipe_back_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/account_fixture.dart';
import '../../support/ui_fixture.dart';

/// The passphrase lock in a fixed state, so its row is offered.
class _Lock extends PassphraseLockController {
  @override
  Future<PassphraseLockState> build() async => PassphraseLockState.off;
}

class _BrokenPreferences extends LocalChatPreferences {
  bool broken = true;
  @override
  bool get available => !broken;
  @override
  Future<void> reset({Iterable<String> baselined = const []}) {
    broken = false;
    return super.reset(baselined: baselined);
  }
}

/// Where each setting lives, as the issue's table says.
const _settings = {
  SettingsCategory.account: ['changePassword', 'signOut', 'deleteAccountTile'],
  SettingsCategory.privacy: ['securityCode', 'passphraseLock', 'blockedPeople'],
  SettingsCategory.notifications: [
    'pushSwitch',
    'pushShowName',
    'pushPreview',
    'pushSound',
    'pushSystemSettings',
    'notificationPreviews',
    'sendSound',
  ],
  SettingsCategory.appearance: ['themeMode', 'chatColors'],
  SettingsCategory.devices: [
    'devices',
    'recoveryKey',
    'lostPhoneWait',
    'linkDevice',
  ],
  SettingsCategory.help: [
    'openPrivacyPolicy',
    'openTermsOfUse',
    'openLicences',
  ],
};

const _pages = {
  SettingsCategory.account: AccountSettingsScreen,
  SettingsCategory.privacy: PrivacySettingsScreen,
  SettingsCategory.notifications: NotificationSettingsScreen,
  SettingsCategory.appearance: AppearanceSettingsScreen,
  SettingsCategory.devices: DevicesSettingsScreen,
  SettingsCategory.help: HelpSettingsScreen,
};

Future<UiFixture> _open(
  WidgetTester t, {
  TargetPlatform platform = TargetPlatform.iOS,
  UiFixture? fixture,
  List<Override> overrides = const [],
  Size size = const Size(800, 2000),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final f = fixture ?? UiFixture(pushNotifications: fixturePush());
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...f.overrides,
        passphraseLockProvider.overrideWith(_Lock.new),
        passphraseLockServiceProvider.overrideWithValue(
          PassphraseLock(WrappingSecretStore(MemorySecretStore())),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light).copyWith(platform: platform),
        home: const SettingsScreen(),
      ),
    ),
  );
  await settleUi(t);
  return f;
}

Future<void> _tapCategory(WidgetTester t, SettingsCategory category) async {
  await t.tap(find.byKey(category.rowKey));
  await t.pumpAndSettle();
  await settleUi(t);
}

void main() {
  testWidgets('the main page has the profile card and the six categories, '
      'and none of the settings themselves', (t) async {
    await _open(t);
    expect(find.byKey(const Key('settingsProfile')), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('Your username'), findsOneWidget);
    for (final category in SettingsCategory.values) {
      expect(find.byKey(category.rowKey), findsOneWidget);
      expect(find.text(category.title), findsOneWidget);
    }
    for (final key in _settings.values.expand((keys) => keys)) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    expect(find.text('Needs attention'), findsNothing);
  });

  for (final category in SettingsCategory.values) {
    testWidgets('${category.title} opens its page with its settings, and '
        'Back returns to the main page', (t) async {
      await _open(t);
      await _tapCategory(t, category);
      expect(find.byType(_pages[category]!), findsOneWidget);
      expect(find.byKey(category.pageKey), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      for (final key in _settings[category]!) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      // No setting shows up on a page the table does not put it on.
      for (final other in _settings.entries) {
        if (other.key == category) continue;
        for (final key in other.value) {
          expect(find.byKey(Key(key)), findsNothing, reason: key);
        }
      }
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(_pages[category]!), findsNothing);
    });
  }

  testWidgets('rows show their current values', (t) async {
    final f = UiFixture(pushNotifications: fixturePush())
      ..takeover.chosen = LostPhoneWait.oneWeek;
    await _open(t, fixture: f);
    String? value(String key) =>
        t.widget<SettingsTile>(find.byKey(Key(key))).value;
    for (final (category, key, expected) in [
      (SettingsCategory.privacy, 'passphraseLock', 'Off'),
      (SettingsCategory.appearance, 'themeMode', 'Light'),
      (SettingsCategory.appearance, 'chatColors', 'Ember'),
      (SettingsCategory.devices, 'lostPhoneWait', '1 week'),
    ]) {
      await _tapCategory(t, category);
      expect(value(key), expected, reason: key);
      expect(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.text(expected),
        ),
        findsOneWidget,
      );
      await t.pageBack();
      await t.pumpAndSettle();
    }
    await _tapCategory(t, SettingsCategory.account);
    expect(find.text('Your username'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
  });

  for (final (scale, iconSize) in [
    (1.35, const Size.square(SettingsIcon.size)),
    (2.0, Size.zero),
  ]) {
    testWidgets('at text scale $scale on a narrow phone the icons are '
        '$iconSize and nothing overflows', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(t, size: const Size(320, 640));
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(SettingsIcon).first), iconSize);
      for (final category in SettingsCategory.values) {
        final row = find.byKey(category.rowKey);
        await t.ensureVisible(row);
        await t.pumpAndSettle();
        await t.tap(row);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: category.title);
        await t.pageBack();
        await t.pumpAndSettle();
      }
    });
  }

  testWidgets('the profile card opens Account', (t) async {
    await _open(t);
    await t.tap(find.byKey(const Key('settingsProfile')));
    await t.pumpAndSettle();
    expect(find.byType(AccountSettingsScreen), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('on Android a category page can be dragged back', (t) async {
    await _open(t, platform: TargetPlatform.android);
    await _tapCategory(t, SettingsCategory.privacy);
    final page = find.byType(PrivacySettingsScreen);
    expect(ModalRoute.of(t.element(page)), isA<SwipeBackPageRoute<void>>());
    await t.flingFrom(const Offset(400, 600), const Offset(200, 0), 800);
    await t.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('on iOS a category page uses the platform route', (t) async {
    await _open(t);
    await _tapCategory(t, SettingsCategory.privacy);
    final route = ModalRoute.of(t.element(find.byType(PrivacySettingsScreen)));
    expect(route, isA<MaterialPageRoute<void>>());
  });

  testWidgets('unreadable local preferences are flagged on the main page and '
      'reset from Notifications, after the confirmation', (t) async {
    final prefs = _BrokenPreferences();
    await _open(t, fixture: UiFixture(chatPreferences: prefs));
    expect(find.text('Needs attention'), findsOneWidget);
    await _tapCategory(t, SettingsCategory.notifications);
    expect(find.text('On this device'), findsOneWidget);
    await t.tap(find.byKey(const Key('resetChatPreferences')));
    await t.pumpAndSettle();
    expect(find.text('Reset local preferences?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(prefs.broken, isTrue);
    await t.tap(find.byKey(const Key('resetChatPreferences')));
    await t.pumpAndSettle();
    await t.tap(find.text('Reset'));
    await settleUi(t);
    await t.pumpAndSettle();
    expect(prefs.broken, isFalse);
    expect(find.byKey(const Key('resetChatPreferences')), findsNothing);
  });

  testWidgets('a failed sign-out says so plainly on Account and can be '
      'tried again', (t) async {
    final auth = ActionAuth()..error = StateError('private detail');
    await _open(t, overrides: [authServiceProvider.overrideWithValue(auth)]);
    await _tapCategory(t, SettingsCategory.account);
    await t.tap(find.byKey(const Key('signOut')));
    await settleUi(t);
    expect(find.byKey(const Key('settingsError')), findsOneWidget);
    expect(find.text('That action did not finish. Try again.'), findsOneWidget);
    expect(find.textContaining('private detail'), findsNothing);
    expect(find.byType(AccountSettingsScreen), findsOneWidget);
    auth.error = null;
    await t.tap(find.byKey(const Key('signOut')));
    await settleUi(t);
    await t.pumpAndSettle();
    expect(auth.signouts, 2);
    expect(find.byType(AccountSettingsScreen), findsNothing);
  });

  for (final page in [
    const SettingsScreen(),
    const AccountSettingsScreen(),
    const DevicesSettingsScreen(),
    const NotificationSettingsScreen(),
  ]) {
    testWidgets('${page.runtimeType} says when the account cannot be loaded, '
        'with Try again', (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var loads = 0;
      await t.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            appSessionProvider.overrideWith((ref) async {
              loads++;
              throw StateError('offline');
            }),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: page,
          ),
        ),
      );
      await settleUi(t);
      expect(find.text('Could not load your account'), findsOneWidget);
      expect(find.textContaining('offline'), findsNothing);
      await t.tap(find.text('Try again'));
      await settleUi(t);
      expect(loads, 2);
    });
  }
}
