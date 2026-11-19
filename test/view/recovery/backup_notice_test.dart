// The recovery key reminder is a notice on the chat list only, with the pill
// buttons of the other notices (issue 201).
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/recovery/backup_notice.dart';
import 'package:fireplace/src/view/recovery/recovery_key_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/account_fixture.dart';
import '../../support/ui_fixture.dart';

void main() {
  final notice = find.byKey(const Key('backupNotice'));

  Future<void> open(WidgetTester t, {bool hasBackup = false}) async {
    final f = UiFixture()..hasBackup = hasBackup;
    await f.seed();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...f.overrides,
          recoveryServiceProvider.overrideWithValue(ActionRecovery()),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const ChatListScreen(header: BackupNotice()),
        ),
      ),
    );
    await settleUi(t);
  }

  testWidgets('shown on the chat list, with pill buttons', (t) async {
    await open(t);
    expect(notice, findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    for (final key in ['backupLater', 'backupCreate']) {
      expect(
        find.ancestor(
          of: find.byKey(Key(key)),
          matching: find.byType(UiNoticeActions),
        ),
        findsOneWidget,
        reason: key,
      );
    }
  });

  testWidgets('not on the pages opened from the chat list', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('settings')));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(notice, findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('conversation-alice_fred')));
    await t.pumpAndSettle();
    expect(notice, findsNothing);
  });

  testWidgets('Later hides it; Create opens the recovery key', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('backupCreate')));
    await t.pumpAndSettle();
    expect(find.byType(RecoveryKeyScreen), findsOneWidget);
    expect(notice, findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('backupLater')));
    await t.pump();
    expect(notice, findsNothing);
  });

  testWidgets('not shown once there is a recovery key', (t) async {
    await open(t, hasBackup: true);
    expect(notice, findsNothing);
  });
}
