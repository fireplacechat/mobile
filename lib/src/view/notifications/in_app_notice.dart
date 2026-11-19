import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/chat_visibility.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/view/notifications/in_app_banner.dart';

/// Foreground-only, one coalesced card that falls in from the top. All
/// navigation is local. It goes when it times out, is swiped up or aside,
/// or is tapped; it vanishes at once when it may no longer be shown.
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final _drop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final _fall = CurvedAnimation(
    parent: _drop,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );
  // How far a finger has pushed the card up, in pixels (negative).
  double _lift = 0;
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

  /// Gone at once: backgrounded, signed out, or no longer allowed.
  void _dismiss() {
    _timer?.cancel();
    _drop.value = 0;
    if (mounted) {
      setState(() {
        _message = null;
        _count = 0;
        _lift = 0;
      });
    }
  }

  /// Back up the way it came, then gone.
  Future<void> _slideAway() async {
    _timer?.cancel();
    final shown = _message;
    if (shown == null) return;
    if (MediaQuery.disableAnimationsOf(context)) return _dismiss();
    await _drop.reverse();
    if (mounted && identical(_message, shown)) _dismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fall.dispose();
    _drop.dispose();
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
        final showing = _message != null;
        setState(() {
          _message = candidates.last;
          _count = showing ? _count + candidates.length : candidates.length;
          _lift = 0;
        });
        // One already down just takes the news; a new one falls in.
        if (!showing || _drop.status == AnimationStatus.reverse) {
          if (MediaQuery.disableAnimationsOf(context)) {
            _drop.value = 1;
          } else {
            _drop.forward(from: showing ? _drop.value : 0);
          }
        }
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 5), _slideAway);
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
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SlideTransition(
                    // From above the top of the screen, with a little bounce
                    // as it lands.
                    position: Tween(
                      begin: const Offset(0, -1.6),
                      end: Offset.zero,
                    ).animate(_fall),
                    child: Transform.translate(
                      offset: Offset(0, _lift),
                      child: Dismissible(
                        key: ValueKey('inAppNotice-${m.id}'),
                        direction: DismissDirection.horizontal,
                        onDismissed: (_) => _dismiss(),
                        child: GestureDetector(
                          onVerticalDragUpdate: (d) => setState(
                            () => _lift = (_lift + d.primaryDelta!).clamp(
                              -200.0,
                              0.0,
                            ),
                          ),
                          onVerticalDragEnd: (d) {
                            if (_lift < -24 ||
                                d.velocity.pixelsPerSecond.dy < -300) {
                              unawaited(_slideAway());
                            } else {
                              setState(() => _lift = 0);
                            }
                          },
                          child: Semantics(
                            liveRegion: true,
                            button: true,
                            onDismiss: _dismiss,
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                key: const Key('inAppNotification'),
                                borderRadius: BorderRadius.circular(22),
                                onTap: () {
                                  // Recheck at tap time; a hold or block may
                                  // have just arrived.
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
                                child: InAppBanner(
                                  title: activity.previewText
                                      ? name
                                      : (_count > 1
                                            ? '$_count new messages'
                                            : 'New message'),
                                  preview: activity.previewText
                                      ? messagePreview(m.body)
                                      : null,
                                  sender: activity.previewText ? name : null,
                                  senderColor: activity.previewText
                                      ? ref
                                            .watch(
                                              acceptedPeerColorProvider(
                                                summary.peerUid,
                                              ),
                                            )
                                            ?.outgoing
                                      : null,
                                  count: activity.previewText ? _count : 1,
                                ),
                              ),
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
