import 'dart:async';
import 'dart:typed_data';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/src/view/devices/devices_screen.dart';
import 'package:fireplace/src/view/devices/recovery_entry_screen.dart';
import 'package:fireplace/src/view/devices/link_wait_screen.dart';
import 'package:fireplace/src/view/recovery/recovery_key_screen.dart';
import 'package:fireplace/src/view/devices/link_new_device_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import '../../support/account_fixture.dart';

Future<void> host(
  WidgetTester t,
  UiFixture f,
  Widget screen, {
  List<Override> extra = const [],
}) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: [...f.overrides, ...extra],
      child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: screen),
    ),
  );
  await settleUi(t);
}

Future<void> flush(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 350));
  await settleUi(t);
}

void main() {
  testWidgets(
    'removal cancellation is harmless and failed removal is guarded/retryable',
    (t) async {
      final k = ActionKeys()
        ..hold = Completer<void>()
        ..error = StateError('private');
      final f = UiFixture(keys: k);
      await host(t, f, const DevicesScreen());
      await t.tap(find.byKey(const Key('revoke_example-second-device')));
      await flush(t);
      // The sheet slides up from the bottom; Cancel is its lowest button.
      await flush(t);
      await t.tap(find.text('Cancel'));
      await flush(t);
      await flush(t);
      expect(k.removals, 0);
      final remove = t
          .widget<IconButton>(
            find.byKey(const Key('revoke_example-second-device')),
          )
          .onPressed!;
      remove();
      remove();
      await flush(t);
      expect(find.text('Remove this device?'), findsOneWidget);
      await flush(t);
      await t.tap(find.byKey(const Key('confirmRevoke')));
      await flush(t);
      expect(k.removals, 1);
      k.hold!.complete();
      await flush(t);
      expect(find.byKey(const Key('deviceActionError')), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
    },
  );
  testWidgets(
    'after removing a device the app asks once whether it was lost; only '
    'that answer resets the security code',
    (t) async {
      final k = ActionKeys();
      final f = UiFixture(keys: k);
      final r = ActionRecovery()..device = f.session.device;
      await host(
        t,
        f,
        const DevicesScreen(),
        extra: [recoveryServiceProvider.overrideWithValue(r)],
      );
      Future<void> remove() async {
        await t.tap(find.byKey(const Key('revoke_example-second-device')));
        await flush(t);
        // One question at a time: nothing about loss before the removal.
        expect(find.text('Was it lost or stolen?'), findsNothing);
        await flush(t);
        await t.tap(find.byKey(const Key('confirmRevoke')));
        // Removed, and the follow-up sheet has slid up.
        await flush(t);
        await flush(t);
      }

      await remove();
      expect(k.removals, 1);
      expect(find.text('Was it lost or stolen?'), findsOneWidget);
      await t.tap(find.byKey(const Key('keepIdentity')));
      await flush(t);
      await flush(t);
      expect(r.resets, 0);
      expect(find.text('Was it lost or stolen?'), findsNothing);

      await remove();
      await t.tap(find.byKey(const Key('resetAfterLoss')));
      await flush(t);
      expect(r.resets, 1);
      // Asked of the server as a device, so it does not have to wait.
      expect(f.takeover.immediateResets, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'password change validates, freezes inputs, retains safe error and guards repeats',
    (t) async {
      final a = ActionAuth()
        ..hold = Completer<void>()
        ..error = StateError('private');
      final f = UiFixture();
      await host(
        t,
        f,
        const SettingsScreen(),
        extra: [authServiceProvider.overrideWithValue(a)],
      );
      await t.ensureVisible(find.byKey(const Key('changePassword')));
      await flush(t);
      await t.tap(find.byKey(const Key('changePassword')));
      await flush(t);
      await t.tap(find.byKey(const Key('pwSave')));
      await flush(t);
      expect(a.passwords, 0);
      await t.enterText(find.byKey(const Key('curPw')), 'old-example-password');
      await t.enterText(find.byKey(const Key('newPw')), 'new-example-password');
      final save = t
          .widget<TextButton>(find.byKey(const Key('pwSave')))
          .onPressed!;
      save();
      save();
      await flush(t);
      expect(a.passwords, 1);
      expect(
        t.widget<TextField>(find.byKey(const Key('curPw'))).enabled,
        isFalse,
      );
      a.hold!.complete();
      await flush(t);
      expect(
        find.text('Could not change your password. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
      a.hold = null;
      a.error = null;
      await t.tap(find.byKey(const Key('pwSave')));
      await flush(t);
      await t.pumpAndSettle();
      expect(a.passwords, 2);
      expect(find.byKey(const Key('pwSave')), findsNothing);
    },
  );
  testWidgets(
    'replacing recovery requires confirmation and leaving an unsaved key is explicit',
    (t) async {
      final r = ActionRecovery();
      final f = UiFixture()..hasBackup = true;
      await host(
        t,
        f,
        const SettingsScreen(),
        extra: [recoveryServiceProvider.overrideWithValue(r)],
      );
      await t.scrollUntilVisible(find.byKey(const Key('recoveryKey')), 250);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('recoveryKey')));
      await flush(t);
      await t.tap(find.byKey(const Key('createRecovery')));
      await flush(t);
      await t.tap(find.text('Cancel'));
      await flush(t);
      expect(r.creations, 0);
      await t.tap(find.byKey(const Key('createRecovery')));
      await flush(t);
      await t.tap(find.byKey(const Key('confirmReplaceRecovery')));
      await flush(t);
      expect(r.creations, 1);
      await t.pageBack();
      await flush(t);
      expect(find.text('Have you saved your recovery key?'), findsOneWidget);
      await t.tap(find.text('Keep it open'));
      await flush(t);
      await t.scrollUntilVisible(
        find.byKey(const Key('savedCheck')),
        250,
        scrollable: find
            .descendant(
              of: find.byType(RecoveryKeyScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pump();
      await t.tap(find.byKey(const Key('savedCheck')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('recoveryDone')));
      await t.pump();
      await t.tap(find.byKey(const Key('recoveryDone')));
      await flush(t);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('recoveryDone')), findsNothing);
    },
  );
  testWidgets('late recovery creation cannot update a disposed screen', (
    t,
  ) async {
    final r = ActionRecovery()..hold = Completer<void>();
    final f = UiFixture();
    await host(
      t,
      f,
      const RecoveryKeyScreen(),
      extra: [recoveryServiceProvider.overrideWithValue(r)],
    );
    final create = t
        .widget<FilledButton>(find.byKey(const Key('createRecovery')))
        .onPressed!;
    create();
    create();
    await t.pump();
    expect(r.creations, 1);
    await t.pumpWidget(const SizedBox());
    r.hold!.complete();
    await flush(t);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'scan cancellation approves nothing and link failure can retry without diagnostics',
    (t) async {
      final r = ActionRecovery()..error = StateError('private');
      final f = UiFixture();
      var scans = 0;
      await host(
        t,
        f,
        LinkNewDeviceScreen(
          scanCode: (_) async => ++scans == 1 ? null : 'example-qr',
        ),
        extra: [recoveryServiceProvider.overrideWithValue(r)],
      );
      await t.scrollUntilVisible(
        find.byKey(const Key('scanLink')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const Key('scanLink')));
      await flush(t);
      expect(r.approvals, 0);
      await t.scrollUntilVisible(
        find.byKey(const Key('scanLink')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const Key('scanLink')));
      await flush(t);
      expect(
        find.text('Could not approve the link. Try again.'),
        findsOneWidget,
      );
      r.error = null;
      await t.scrollUntilVisible(
        find.byKey(const Key('scanLink')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const Key('scanLink')));
      await flush(t);
      expect(find.byKey(const Key('linkApproved')), findsOneWidget);
      expect(find.text('Device linked'), findsOneWidget);
      expect(find.byKey(const Key('scanLink')), findsNothing);
      expect(r.approvals, 2);
    },
  );
  testWidgets(
    'the new device finishes by itself when the answer arrives, and a refused answer can be tried again',
    (t) async {
      final r = ActionRecovery();
      final f = UiFixture();
      r.request = LinkRequest(
        'alice',
        f.session.device.keys,
        Uint8List(16),
        'example-qr',
      );
      final answer = SealedIdentity(
        ek: Uint8List(32),
        kemCt: Uint8List(8),
        nonce: Uint8List(12),
        ct: Uint8List(8),
        mac: Uint8List(16),
      );
      r.response = Completer<SealedIdentity>();
      r.error = RecoveryException('Could not link this device. Start again.');
      await host(
        t,
        f,
        const LinkWaitScreen(uid: 'alice'),
        extra: [recoveryServiceProvider.overrideWithValue(r)],
      );
      expect(find.text('Waiting for approval…'), findsOneWidget);
      // Nothing to type: no field and no button besides the QR code.
      expect(find.byType(TextField), findsNothing);
      r.response!.complete(answer);
      await flush(t);
      expect(r.completions, 1);
      expect(
        find.text('Could not link this device. Start again.'),
        findsOneWidget,
      );
      expect(find.text('Linking…'), findsNothing);
      r.error = null;
      r.response = Completer<SealedIdentity>()..complete(answer);
      await t.tap(find.byKey(const Key('retryLink')));
      await flush(t);
      expect(r.starts, 2);
      expect(r.completions, 2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'expired link retries and late-created request is cleaned up after disposal',
    (t) async {
      final r = ActionRecovery();
      final f = UiFixture();
      r.request = LinkRequest(
        'alice',
        f.session.device.keys,
        Uint8List(16),
        'example-qr',
      );
      r.response = Completer<SealedIdentity>();
      await host(
        t,
        f,
        const LinkWaitScreen(uid: 'alice'),
        extra: [recoveryServiceProvider.overrideWithValue(r)],
      );
      r.response!.completeError(
        RecoveryException('This link request expired.'),
      );
      await flush(t);
      expect(find.byKey(const Key('retryLink')), findsOneWidget);
      expect(find.text('Waiting for approval…'), findsNothing);
      r.startHold = Completer<LinkRequest>();
      await t.tap(find.byKey(const Key('retryLink')));
      await flush(t);
      expect(r.starts, 2);
      expect(r.canceled.length, 1);
      await t.pumpWidget(const SizedBox());
      r.startHold!.complete(r.request);
      await flush(t);
      expect(r.canceled.length, 2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('restoration is guarded and late failures are safe', (t) async {
    final r = ActionRecovery()
      ..hold = Completer<void>()
      ..error = RecoveryException('Key did not match.');
    final f = UiFixture();
    await host(
      t,
      f,
      const RecoveryEntryScreen(uid: 'alice'),
      extra: [recoveryServiceProvider.overrideWithValue(r)],
    );
    await t.enterText(find.byKey(const Key('recoveryInput')), 'EXAMPLE');
    final restore = t
        .widget<FilledButton>(find.byKey(const Key('recoverGo')))
        .onPressed!;
    restore();
    restore();
    await flush(t);
    expect(r.restores, 1);
    expect(
      t.widget<TextField>(find.byKey(const Key('recoveryInput'))).enabled,
      isFalse,
    );
    await t.pumpWidget(const SizedBox());
    r.hold!.complete();
    await flush(t);
    expect(t.takeException(), isNull);
  });
}
