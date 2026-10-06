import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/status.dart';

String _reasonLabel(ReportReason r) => switch (r) {
  ReportReason.spam => 'Spam or unwanted promotion',
  ReportReason.harassment => 'Harassment or threats',
  ReportReason.abuse => 'Abusive or illegal content',
  ReportReason.impersonation => 'Pretending to be someone else',
  ReportReason.other => 'Something else',
};

/// Reports a person to the app operator. Because messages are end-to-end
/// encrypted, the operator only sees message text the reporter chooses to attach.
Future<bool> showReportDialog(
  BuildContext context,
  WidgetRef ref, {
  required String peerUid,
  required String name,
  String? chatId,

  /// Set when the report starts from one message (long press > Report): the tick box then offers
  /// to include just that message instead of the last ten.
  LocalMessage? focus,
}) async {
  final session = ref.read(appSessionProvider).value;
  if (session == null) return false;
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(
      name: name,
      canIncludeChat: chatId != null,
      aboutMessage: focus != null,
      submit: (input) async {
        void checkAccount() {
          if (!context.mounted ||
              !identical(ref.read(appSessionProvider).value, session)) {
            throw StateError('Account changed');
          }
        }

        checkAccount();
        var context10 = <String>[];
        if (input.include && focus != null) {
          if (focus.status == MessageStatus.ok) {
            context10 = [
              '${focus.outgoing ? 'reporter' : 'reported'}: ${focus.body}',
            ];
          }
        } else if (input.include && chatId != null) {
          final msgs = await session.chat.watchMessages(chatId).first;
          final tail = msgs.length > 10 ? msgs.sublist(msgs.length - 10) : msgs;
          context10 = [
            for (final m in tail)
              if (m.status == MessageStatus.ok)
                '${m.outgoing ? 'reporter' : 'reported'}: ${m.body}',
          ];
        }
        checkAccount();
        await session.safety.report(
          peerUid: peerUid,
          reason: input.reason,
          chatId: chatId,
          note: input.note,
          context: context10,
        );
      },
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Report sent. Thank you.')));
  }
  return sent == true;
}

class _ReportInput {
  _ReportInput(this.reason, this.note, this.include);
  final ReportReason reason;
  final String note;
  final bool include;
}

/// Owns its text controller so it is disposed only after the dialog is gone.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.name,
    required this.canIncludeChat,
    required this.submit,
    this.aboutMessage = false,
  });
  final bool aboutMessage;
  final Future<void> Function(_ReportInput) submit;
  final String name;
  final bool canIncludeChat;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _note = TextEditingController();
  var _reason = ReportReason.spam;
  var _include = false;
  bool _busy = false;
  String? _error;
  Future<void> _send() async {
    if (_busy) return;
    final input = _ReportInput(_reason, _note.text, _include);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(input);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not send the report. Your choices are kept here. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: UiDialog(
      title: Text('Report @${widget.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) {
                if (!_busy) setState(() => _reason = v ?? _reason);
              },
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      key: Key('reason_${r.name}'),
                      enabled: !_busy,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: r,
                      title: Text(_reasonLabel(r)),
                    ),
                ],
              ),
            ),
            TextField(
              key: Key('reportNote'),
              controller: _note,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Details (optional)'),
            ),
            if (widget.canIncludeChat)
              CheckboxListTile(
                key: Key('reportInclude'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _include,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _include = v ?? false),
                title: Text(
                  widget.aboutMessage
                      ? 'Include this message'
                      : 'Include up to 10 recent readable messages',
                ),
                subtitle: FireplaceBrandText(
                  widget.aboutMessage
                      ? 'If ticked, this message is shared as text with the Fireplace team. This option starts off.'
                      : 'If ticked, selected readable messages are shared as text with the Fireplace team. This option starts off.',
                ),
              ),
            if (_error != null)
              UiActionError(key: const Key('reportError'), message: _error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          key: Key('sendReport'),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Sending…' : 'Send report'),
        ),
      ],
    ),
  );
}
