import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/status.dart';

class RequestBanner extends StatelessWidget {
  const RequestBanner({
    super.key,
    required this.name,
    required this.onAccept,
    required this.onBlock,
    required this.onReport,
    this.busy = false,
  });
  final bool busy;
  final String name;
  final VoidCallback onAccept, onBlock, onReport;
  @override
  Widget build(BuildContext context) => UiNotice(
    key: const Key('requestBanner'),
    warning: true,
    text:
        '@$name wants to chat. You will not see their messages until you accept. They will not be told whether you looked.',
    actions: [
      FilledButton(
        key: const Key('acceptRequest'),
        onPressed: busy ? null : onAccept,
        child: Text(busy ? 'Working…' : 'Accept'),
      ),
      OutlinedButton(
        key: const Key('blockRequest'),
        onPressed: busy ? null : onBlock,
        child: const Text('Block'),
      ),
      TextButton(
        key: const Key('reportRequest'),
        onPressed: busy ? null : onReport,
        child: const Text('Report'),
      ),
    ],
  );
}
