import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/model/chat/message_recovery_action.dart';

/// The warning under an outgoing message whose delivery is not known. It never shows a
/// sent or read tick, never invites a plain retry, and its actions cannot publish by accident.
class UnconfirmedNote extends StatelessWidget {
  const UnconfirmedNote({
    super.key,
    required this.messageId,
    required this.savedLocallyFailed,
    required this.action,
    required this.note,
    required this.onCheck,
    required this.onSendAgain,
    required this.onSave,
  });
  final String messageId;
  final bool savedLocallyFailed;
  final MessageRecoveryAction? action;
  final String? note;
  final VoidCallback onCheck;
  final VoidCallback onSendAgain;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final theme = Theme.of(context);
    final title = savedLocallyFailed
        ? 'Sent — could not save on this device'
        : 'Message not confirmed';
    final detail = savedLocallyFailed
        ? 'Your message was sent. Do not send it again.'
        : 'This message may have reached them. Sending it again could create a duplicate.';
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: ValueKey('unconfirmed-$messageId'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: t.warningSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: t.danger),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      title,
                      key: const Key('unconfirmedTitle'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodySmall),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(
                note!,
                key: const Key('checkNote'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            Wrap(
              children: [
                if (savedLocallyFailed)
                  TextButton(
                    key: const Key('saveOnDevice'),
                    onPressed: action == null ? onSave : null,
                    child: Text(
                      action == MessageRecoveryAction.saving
                          ? 'Saving…'
                          : 'Save on this device',
                    ),
                  )
                else ...[
                  TextButton(
                    key: const Key('checkSendStatus'),
                    onPressed: action == null ? onCheck : null,
                    child: Text(
                      action == MessageRecoveryAction.checking
                          ? 'Checking…'
                          : 'Check status',
                    ),
                  ),
                  TextButton(
                    key: const Key('resendUnconfirmed'),
                    onPressed: action == null ? onSendAgain : null,
                    child: Text(
                      action == MessageRecoveryAction.resending
                          ? 'Sending…'
                          : 'Send again…',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
