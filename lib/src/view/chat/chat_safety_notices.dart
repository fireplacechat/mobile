import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fireplace/src/model/chat/contact_controller.dart';
import 'package:fireplace/src/model/chat/send_controller.dart';
import 'package:fireplace/src/view/chat/widgets/identity_alert_banner.dart';
import 'package:fireplace/src/view/chat/widgets/new_device_banner.dart';
import 'package:fireplace/src/view/chat/widgets/request_banner.dart';
import 'package:fireplace/src/widgets/status.dart';

class SearchLocationNotice extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  SearchLocationNotice({
    super.key,
    required this.target,
    required this.onShowLatest,
  });
  final int target;
  final VoidCallback onShowLatest;
  @override
  Widget build(BuildContext context) => UiNotice(
    key: const Key('searchLocation'),
    text: target < 0
        ? 'This search result is no longer on this device.'
        : 'Search result — showing messages up to this point.',
    actions: [
      TextButton(
        onPressed: onShowLatest,
        child: const Text('Show latest messages'),
      ),
    ],
  );
}

class ChatSafetyNotices extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatSafetyNotices({
    super.key,
    required this.peerUid,
    required this.name,
    required this.hasSession,
    required this.incomingRequest,
    required this.outgoingPending,
    required this.waiting,
    required this.requestsLeft,
    required this.contact,
    required this.send,
    required this.keyboardInset,
    required this.onReviewIdentity,
    required this.onAccept,
    required this.onBlock,
    required this.onReport,
  });
  final String? peerUid;
  final String name;
  final bool hasSession, incomingRequest, outgoingPending, waiting;
  final double keyboardInset;
  final int requestsLeft;
  final ContactController contact;
  final SendController send;
  final Future<void> Function(List<int>) onReviewIdentity;
  final Future<void> Function() onAccept, onBlock, onReport;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: math.max(
        48,
        (MediaQuery.sizeOf(context).height - keyboardInset) *
            (MediaQuery.sizeOf(context).height > 650 ? .45 : .33),
      ),
    ),
    child: SingleChildScrollView(
      key: const Key('chatSafetyNotices'),
      child: Column(
        children: [
          if (peerUid != null && hasSession)
            IdentityAlertBanner(
              peerUid: peerUid!,
              name: name,
              busy: contact.reviewing,
              onReview: onReviewIdentity,
            ),
          if (peerUid != null) NewDeviceBanner(peerUid: peerUid!, name: name),
          if (incomingRequest && hasSession && peerUid != null)
            RequestBanner(
              name: name,
              busy: contact.busy,
              onAccept: onAccept,
              onBlock: onBlock,
              onReport: onReport,
            ),
          if (contact.error != null)
            UiNotice(warning: true, text: contact.error!),
          if (send.sendError != null)
            UiNotice(
              key: const Key('sendFailure'),
              warning: true,
              brandText: true,
              text: send.sendError!,
              actions: [
                TextButton(
                  onPressed: () => send.dismissError(),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          if (outgoingPending && !waiting)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Message request sent. @$name sees it once they accept '
                '($requestsLeft left).',
                key: Key('requestSentNote'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    ),
  );
}
