import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';

class ChatUnavailableScreen extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatUnavailableScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(
      context: context,
      title: const Text('Conversation unavailable'),
    ),
    body: UiEmptyState(
      title: 'Return to your chats',
      message: 'Your account changed or is not ready. Open the conversation again from your chat list.',
      action: TextButton(
        onPressed: () =>
            Navigator.of(context).popUntil((route) => route.isFirst),
        child: const Text('Return to chats'),
      ),
    ),
  );
}

class ChatPrivacyErrorScreen extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatPrivacyErrorScreen({
    super.key,
    required this.loading,
    required this.onRetry,
  });
  final bool loading;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context, title: const Text('Conversation')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : UiEmptyState(
            title: 'Could not load privacy settings',
            message: 'Your conversation stays hidden until these settings are available.',
            action: TextButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ),
  );
}
