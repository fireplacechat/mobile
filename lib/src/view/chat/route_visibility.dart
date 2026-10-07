import 'package:flutter/widgets.dart';
import 'package:fireplace/src/model/chat/chat_visibility.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart'
    show chatRouteObserver;

class RouteVisibility with RouteAware, WidgetsBindingObserver {
  RouteVisibility({
    required this.chatId,
    required this.notifier,
    required this.currentlyVisible,
    required this.isMounted,
    required this.onVisible,
  });
  final String Function() chatId;
  final ChatVisibility notifier;
  final String? Function() currentlyVisible;
  final bool Function() isMounted;
  final void Function() onVisible;
  ModalRoute<void>? _route;
  bool _foreground = true;
  bool get foreground => _foreground;
  bool get isCurrentRoute => _route?.isCurrent ?? false;

  void start() {
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void subscribe(ModalRoute<void> route) {
    if (route != _route) {
      chatRouteObserver.unsubscribe(this);
      _route = route;
      chatRouteObserver.subscribe(this, route);
    }
  }

  void _visibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) {
        this.notifier.clearIf(chatId());
        return;
      }
      final visible = _foreground && (_route?.isCurrent ?? false);
      final notifier = this.notifier;
      if (visible) {
        notifier.show(chatId());
        onVisible();
      } else if (currentlyVisible() == chatId()) {
        notifier.show(null);
      }
    });
  }

  @override
  void didPush() => _visibility();
  @override
  void didPushNext() => _visibility();
  @override
  void didPopNext() => _visibility();
  @override
  void didPop() => _visibility();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visibility();
  }

  void dispose() {
    chatRouteObserver.unsubscribe(this);
    final id = chatId();
    final visibility = notifier;
    WidgetsBinding.instance.addPostFrameCallback((_) => visibility.clearIf(id));
    WidgetsBinding.instance.removeObserver(this);
  }
}
