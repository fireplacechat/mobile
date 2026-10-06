import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/services/chat_service.dart';
import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/widgets/dialog.dart';

class StartChatDialog extends ConsumerStatefulWidget {
  const StartChatDialog({super.key});
  @override
  ConsumerState<StartChatDialog> createState() => _StartChatDialogState();
}

class _StartChatDialogState extends ConsumerState<StartChatDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a username.');
      return;
    }
    if (!AuthService.isValidUsername(name)) {
      setState(() => _error = 'Use 3–20 letters, numbers or underscores.');
      return;
    }
    final session = ref.read(appSessionProvider).value;
    if (session == null) {
      setState(() => _error = 'Your account is not ready yet.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await session.chat.startChat(name);
      if (mounted) Navigator.pop(context, id);
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start chat. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    title: Text('Start a chat'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: Key('peerUsername'),
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: "Friend's username",
              helperText: '3–20 letters, numbers or underscores',
              helperMaxLines: 2,
              errorMaxLines: 3,
              errorText: _error,
            ),
            onSubmitted: (_) => _start(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text('Cancel'),
      ),
      FilledButton(
        key: Key('startChat'),
        onPressed: _busy ? null : _start,
        child: Text(_busy ? 'Starting…' : 'Start'),
      ),
    ],
  );
}
