import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fireplace/src/model/chat/send_controller.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/composer/message_input_formatter.dart';
import 'package:fireplace/src/view/chat/widgets/composer_note.dart';

class ChatComposer extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatComposer({
    super.key,
    required this.keyboardInset,
    required this.text,
    required this.name,
    required this.blocked,
    required this.incomingRequest,
    required this.waiting,
    required this.identityHeld,
    required this.hasSession,
    required this.contactBusy,
    required this.send,
    required this.onUnblock,
  });
  final double keyboardInset;
  final TextEditingController text;
  final String name;
  final bool blocked,
      incomingRequest,
      waiting,
      identityHeld,
      hasSession,
      contactBusy;
  final SendController send;
  final Future<void> Function() onUnblock;
  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return ComposerNote(
        key: Key('blockedNote'),
        text: 'You blocked @$name.',
        action: TextButton(
          onPressed: !hasSession || contactBusy ? null : onUnblock,
          child: Text('Unblock'),
        ),
      );
    } else if (incomingRequest) {
      return ComposerNote(
        key: Key('acceptToReplyNote'),
        text: 'Accept this request to reply.',
      );
    } else if (waiting) {
      return ComposerNote(
        key: Key('waitingNote'),
        text: 'Waiting for @$name to accept your request.',
      );
    } else if (identityHeld) {
      return ComposerNote(
        key: Key('identityHeldNote'),
        text: 'Review this contact’s security code before sending.',
      );
    } else {
      return SafeArea(
        top: false,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                send.send,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                send.send,
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: FireplaceUiTokens.of(context).panel,
              border: Border(
                top: BorderSide(color: FireplaceUiTokens.of(context).separator),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          ((MediaQuery.sizeOf(context).height - keyboardInset) *
                                  .35)
                              .clamp(120, 280),
                    ),
                    child: TextField(
                      key: Key('composer'),
                      controller: text,
                      inputFormatters: [MessageInputFormatter()],
                      minLines: 1,
                      maxLines:
                          MediaQuery.sizeOf(context).height - keyboardInset <
                              500
                          ? 3
                          : 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        counter:
                            messageCharacters(text.text) >=
                                (maxMessageCharacters * .9).floor()
                            ? Text(
                                '${messageCharacters(text.text)} / 16,384',
                                key: const Key('messageCounter'),
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : null,
                        hintText: 'Message',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton.filled(
                  key: Key('send'),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed:
                      send.sending || text.text.trim().isEmpty || !hasSession
                      ? null
                      : send.send,
                  tooltip: send.sending ? 'Sending message' : 'Send message',
                  icon: send.sending
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}
