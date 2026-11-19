// Reporting spam from the chat details screen (issue 120): cancelling sends
// nothing, a report says so, report-and-block also blocks and leaves the
// details, and a report that cannot reach the server says it did not go.
import 'package:fireplace/src/view/chat/chat_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'chat_screen_helpers_pinning_test.dart' show RecordingSafety;
import 'chat_screen_pinning_test.dart' show host;

class ReportingSafety extends RecordingSafety {
  final reports = <String>[];
  Object? error;

  @override
  Future<void> reportSpam(String peerUid) async {
    if (error case final e?) throw e;
    reports.add(peerUid);
  }
}

Future<ReportingSafety> openReport(WidgetTester t, {Object? error}) async {
  final safety = ReportingSafety()..error = error;
  await host(t, UiFixture(safety: safety)..blocked = {});
  await t.tap(find.byKey(const Key('chatDetails')));
  await t.pumpAndSettle();
  await t.ensureVisible(find.byKey(const Key('detailsReport')));
  await t.tap(find.byKey(const Key('detailsReport')));
  await t.pumpAndSettle();
  return safety;
}

void main() {
  testWidgets('cancelling sends no report', (t) async {
    final safety = await openReport(t);
    await t.tap(find.byKey(const Key('cancelReportSpam')));
    await settleUi(t);
    expect(safety.reports, isEmpty);
    expect(safety.blocks, isEmpty);
    expect(find.byType(ChatDetailsScreen), findsOneWidget);
  });

  testWidgets('a report says it was sent', (t) async {
    final safety = await openReport(t);
    await t.tap(find.byKey(const Key('confirmReportSpam')));
    await settleUi(t);
    expect(safety.reports, ['fred']);
    expect(safety.blocks, isEmpty);
    expect(find.text('Reported as spam.'), findsOneWidget);
  });

  testWidgets('report and block blocks too and leaves the details', (t) async {
    final safety = await openReport(t);
    await t.tap(find.byKey(const Key('confirmReportAndBlock')));
    await settleUi(t);
    await t.pumpAndSettle();
    expect(safety.reports, ['fred']);
    expect(safety.blocks, ['fred']);
    expect(find.byType(ChatDetailsScreen), findsNothing);
    expect(find.text('Reported as spam and blocked.'), findsOneWidget);
  });

  testWidgets('a report that cannot reach the server says so and does not '
      'block', (t) async {
    final safety = await openReport(t, error: Exception('unavailable'));
    await t.tap(find.byKey(const Key('confirmReportAndBlock')));
    await settleUi(t);
    expect(safety.reports, isEmpty);
    expect(safety.blocks, isEmpty);
    expect(find.byType(ChatDetailsScreen), findsOneWidget);
    expect(
      find.text('Could not send the spam report. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Reported as spam.'), findsNothing);
  });
}
