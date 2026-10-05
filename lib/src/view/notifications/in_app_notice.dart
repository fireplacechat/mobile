import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/ui/message_format.dart';

/// Foreground-only, one coalesced card. All navigation is local.
class InAppNoticeHost extends ConsumerStatefulWidget {
  const InAppNoticeHost({
    super.key,
    required this.child,
    required this.navigatorKey,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  @override
  ConsumerState<InAppNoticeHost> createState() => _InAppNoticeHostState();
}

class _InAppNoticeHostState extends ConsumerState<InAppNoticeHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  LocalMessage? _message;
  int _count = 0;
  bool _handling = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _dismiss();
  }

  void _dismiss() {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _message = null;
        _count = 0;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(chatActivityProvider);
    final visible = ref.watch(visibleChatProvider);
    ref.listen(appSessionProvider, (previous, next) {
      if (previous?.value?.uid != next.value?.uid) _dismiss();
    });
    ref.listen(chatActivityProvider, (_, next) {
      if (next.arrivals.isEmpty || _handling) return;
      _handling = true;
      final owner = ref.read(appSessionProvider).value?.uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handling = false;
        final latest = ref.read(chatActivityProvider);
        final candidates = latest.arrivals
            .where(
              (m) =>
                  _foreground &&
                  m.chatId != ref.read(visibleChatProvider) &&
                  !latest.muted.contains(m.chatId),
            )
            .toList();
        ref.read(chatActivityProvider.notifier).dismissArrivals();
        if (candidates.isEmpty ||
            !_foreground ||
            owner != ref.read(appSessionProvider).value?.uid) {
          return;
        }
        setState(() {
          _message = candidates.last;
          _count = candidates.length;
        });
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 5), _dismiss);
      });
    });
    final m = _message;
    final summary = m == null ? null : ref.watch(chatSummaryProvider(m.chatId));
    final allowed =
        m != null &&
        activity.preferencesAvailable &&
        _foreground &&
        visible != m.chatId &&
        !activity.muted.contains(m.chatId) &&
        summary != null &&
        ref.read(chatActivityProvider.notifier).eligible(summary);
    if (m != null && !allowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_message, m)) _dismiss();
      });
    }
    final name = summary == null
        ? ''
        : ref.watch(peerUsernameProvider(summary.peerUid)).value ??
              'New message';
    return Overlay.wrap(
      child: Stack(
        children: [
          widget.child,
          if (allowed)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: (MediaQuery.sizeOf(context).height * .35).clamp(
                      80,
                      240,
                    ),
                  ),
                  child: Dismissible(
                    key: ValueKey('inAppNotice-${m.id}'),
                    direction: DismissDirection.horizontal,
                    onDismissed: (_) => _dismiss(),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: -20, end: 0),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      builder: (_, offset, child) => Transform.translate(
                        offset: Offset(0, offset),
                        child: child,
                      ),
                      child: Material(
                        elevation: 8,
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          child: Semantics(
                            liveRegion: true,
                            child: ListTile(
                              key: const Key('inAppNotification'),
                              leading: const Icon(Icons.chat_bubble_outline),
                              title: Text(
                                activity.previewText
                                    ? name
                                    : (_count > 1
                                          ? '$_count new messages'
                                          : 'New message'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: activity.previewText
                                  ? Text(
                                      messagePreview(m.body),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              trailing: IconButton(
                                tooltip: 'Dismiss notification',
                                icon: const Icon(Icons.close),
                                onPressed: _dismiss,
                              ),
                              onTap: () {
                                // Recheck at tap time; a hold or block may have just arrived.
                                final current = ref.read(
                                  chatSummaryProvider(m.chatId),
                                );
                                if (current == null ||
                                    !ref
                                        .read(chatActivityProvider.notifier)
                                        .eligible(current)) {
                                  _dismiss();
                                  return;
                                }
                                _dismiss();
                                widget.navigatorKey.currentState?.push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        ChatScreen(chatId: m.chatId),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
