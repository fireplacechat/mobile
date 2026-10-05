import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One extensible message action, shared by touch, desktop and accessibility.
class MessageAction {
  const MessageAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });
  final String id, label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

Future<void> showMessageActionsMenu(
  BuildContext context, {
  required Offset globalPosition,
  required List<MessageAction> actions,
}) async {
  if (actions.isEmpty || !context.mounted) return;
  // Haptics are an enhancement; platform failures must not prevent the menu.
  HapticFeedback.selectionClick().catchError((Object _) {});
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  final error = Theme.of(context).colorScheme.error;
  final chosen = await showMenu<MessageAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(local.dx, local.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final a in actions)
        PopupMenuItem<MessageAction>(
          key: ValueKey('messageAction-${a.id}'),
          value: a,
          child: Row(
            children: [
              Icon(a.icon, size: 20, color: a.destructive ? error : null),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  a.label,
                  style: a.destructive ? TextStyle(color: error) : null,
                ),
              ),
            ],
          ),
        ),
    ],
  );
  if (context.mounted) chosen?.onSelected();
}

/// Selection lives in its own sheet so it cannot compete with long-press actions.
Future<void> showSelectTextSheet(
  BuildContext context,
  String text, {
  Widget Function(BuildContext, Widget)? protectSelection,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (ctx) {
    final media = MediaQuery.of(ctx);
    final available =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                40)
            .clamp(0.0, media.size.height);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: available * .7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select text',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (protectSelection == null)
                SelectableText(
                  text,
                  key: const Key('selectableMessageText'),
                  style: const TextStyle(fontSize: 17, height: 1.45),
                )
              else
                protectSelection(
                  ctx,
                  SelectableText(
                    text,
                    key: const Key('selectableMessageText'),
                    style: const TextStyle(fontSize: 17, height: 1.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  },
);
