import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/widgets/status.dart';

/// Shown while a contact's changed identity key is holding up their messages.

class IdentityAlertBanner extends ConsumerWidget {
  const IdentityAlertBanner({
    super.key,
    required this.peerUid,
    required this.name,
    required this.onReview,
    this.busy = false,
  });
  final String peerUid, name;
  final bool busy;
  final void Function(List<int> newIdentityPub) onReview;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pub = ref.watch(identityAlertsProvider).value?[peerUid];
    if (pub == null) return const SizedBox.shrink();
    return UiNotice(
      key: const Key('identityBanner'),
      warning: true,
      text:
          "@$name's security code changed. Messages are on hold until you review it.",
      actions: [
        TextButton(
          key: const Key('reviewIdentity'),
          onPressed: busy ? null : () => onReview(pub),
          child: Text(busy ? 'Reviewing…' : 'Review'),
        ),
      ],
    );
  }
}
