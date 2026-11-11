import 'package:flutter/material.dart';

import 'package:fireplace/src/view/safety/safety_action_sheet.dart';

enum ReportSpamChoice { report, reportAndBlock }

/// Signal's "Report Spam?" panel.
///
/// The report itself names the account. The panel says the app cannot see
/// the chats, and it never asks for message text.
Future<ReportSpamChoice?> confirmReportSpam(
  BuildContext context, {
  required bool blocked,
}) {
  return showSafetyActionSheet<ReportSpamChoice>(
    context: context,
    title: 'Report Spam?',
    message:
        'Fireplace will be notified that this person may be sending spam. '
        "Fireplace can't see the content of any chats.",
    actions: [
      const SafetySheetAction(
        label: 'Report Spam',
        value: ReportSpamChoice.report,
        buttonKey: Key('confirmReportSpam'),
      ),
      if (!blocked)
        const SafetySheetAction(
          label: 'Report Spam and Block',
          value: ReportSpamChoice.reportAndBlock,
          buttonKey: Key('confirmReportAndBlock'),
        ),
      const SafetySheetAction(
        label: 'Cancel',
        buttonKey: Key('cancelReportSpam'),
      ),
    ],
  );
}
