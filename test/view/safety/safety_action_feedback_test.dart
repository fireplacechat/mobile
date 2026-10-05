import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/ui/safety_ui.dart';
import 'package:fireplace/src/view/chat/chat_details_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

class RecordingSafety extends FixtureSafety {
  final reports = <(ReportReason, String?, List<String>)>[];
  final unblocks = <String>[];
  Completer<void>? hold;
  Object? error;
  @override
  Future<void> report({
    required String peerUid,
    required ReportReason reason,
    String? chatId,
    String? note,
    List<String> context = const [],
  }) async {
    reports.add((reason, note, List.of(context)));
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> unblock(String uid) async {
    unblocks.add(uid);
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
  }
}

class RecordingKeys extends FixtureKeys {
  int verifies = 0;
  Completer<void>? hold;
  Object? error;
  @override
  Future<void> markVerified(String uid, List<int> identity) async {
    verifies++;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
  }
}

Future<void> host(WidgetTester t, UiFixture f, Widget screen) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: screen),
    ),
  );
  await settleUi(t);
}

Widget details() => ChatDetailsScreen(
  peerUid: 'fred',
  chatId: 'alice_fred',
  name: 'fred',
  onBlock: () async {},
  onUnblock: () async {},
);
Future<void> openReport(WidgetTester t) async {
  await t.tap(find.byKey(const Key('detailsReport')));
  await t.pump(const Duration(milliseconds: 350));
  await settleUi(t);
}

Future<void> submitReport(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('sendReport')));
  await t.pump();
  await t.tap(find.byKey(const Key('sendReport')));
  await settleUi(t);
}

void main() {
  testWidgets('cancel sends nothing; default report shares no message text', (
    t,
  ) async {
    final s = RecordingSafety();
    final f = UiFixture(safety: s);
    await f.seed();
    await host(t, f, details());
    await openReport(t);
    expect(
      t.widget<CheckboxListTile>(find.byKey(const Key('reportInclude'))).value,
      isFalse,
    );
    await t.ensureVisible(find.text('Cancel'));
    await t.pump();
    await t.tap(find.text('Cancel'));
    await t.pump(const Duration(milliseconds: 350));
    await settleUi(t);
    expect(s.reports, isEmpty);
    await openReport(t);
    await submitReport(t);
    expect(s.reports.single.$3, isEmpty);
  });
  testWidgets(
    'failed report preserves reason, note and explicit context and guards repeats',
    (t) async {
      final s = RecordingSafety()
        ..error = StateError('private error')
        ..hold = Completer<void>();
      final f = UiFixture(safety: s);
      await f.seed();
      await host(t, f, details());
      await openReport(t);
      await t.tap(find.byKey(const Key('reason_harassment')));
      await t.enterText(
        find.byKey(const Key('reportNote')),
        'Unwanted messages',
      );
      await t.ensureVisible(find.byKey(const Key('reportInclude')));
      await t.pump();
      await t.tap(find.byKey(const Key('reportInclude')));
      final send = t
          .widget<TextButton>(find.byKey(const Key('sendReport')))
          .onPressed!;
      send();
      send();
      await settleUi(t);
      expect(s.reports.length, 1);
      expect(s.reports.single.$3.length, 5);
      expect(
        t.widget<TextField>(find.byKey(const Key('reportNote'))).enabled,
        isFalse,
      );
      s.hold!.complete();
      await settleUi(t);
      expect(find.byKey(const Key('reportError')), findsOneWidget);
      expect(find.textContaining('private error'), findsNothing);
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('reportInclude')))
            .value,
        isTrue,
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('reportNote')))
            .controller!
            .text,
        'Unwanted messages',
      );
      expect(s.reports.single.$1, ReportReason.harassment);
      s.hold = null;
      s.error = null;
      await submitReport(t);
      expect(s.reports.length, 2);
      expect(find.byKey(const Key('sendReport')), findsNothing);
    },
  );
  testWidgets(
    'blocked contact failures are retained and unblocking is guarded',
    (t) async {
      final s = RecordingSafety()
        ..hold = Completer<void>()
        ..error = StateError('private');
      final f = UiFixture(safety: s)..blocked = {'fred'};
      await host(t, f, const BlockedUsersScreen());
      final unblock = t
          .widget<TextButton>(find.byKey(const Key('unblock_fred')))
          .onPressed!;
      unblock();
      unblock();
      await t.pump();
      expect(s.unblocks, ['fred']);
      s.hold!.complete();
      await settleUi(t);
      expect(
        find.text('Could not unblock this person. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
    },
  );
  testWidgets(
    'mismatched scan never marks verified and manual verification is guarded',
    (t) async {
      final k = RecordingKeys();
      final f = UiFixture(keys: k);
      await host(
        t,
        f,
        VerifyScreen(
          peerUid: 'fred',
          peerName: 'fred',
          scanCode: (_) async => 'not-a-verification-code',
        ),
      );
      await t.scrollUntilVisible(find.byKey(const Key('scan')), 250);
      await t.pump(const Duration(milliseconds: 350));
      await settleUi(t);
      await t.tap(find.byKey(const Key('scan')));
      await t.pump(const Duration(milliseconds: 350));
      await settleUi(t);
      expect(find.text("Codes don't match"), findsOneWidget);
      expect(k.verifies, 0);
      await t.tap(find.text('OK'));
      await t.pump(const Duration(milliseconds: 350));
      await settleUi(t);
      await t.ensureVisible(find.byKey(const Key('toggleVerified')));
      await t.pump(const Duration(milliseconds: 350));
      await settleUi(t);
      k.hold = Completer<void>();
      k.error = StateError('private');
      final verify = t
          .widget<OutlinedButton>(find.byKey(const Key('toggleVerified')))
          .onPressed!;
      verify();
      verify();
      await t.pump();
      expect(k.verifies, 1);
      k.hold!.complete();
      await settleUi(t);
      expect(find.byKey(const Key('verificationError')), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
    },
  );
}
