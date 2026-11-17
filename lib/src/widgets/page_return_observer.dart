import 'package:flutter/widgets.dart';

/// Tells a screen when a full page that covered it closes and it is in view
/// again. Menus, sheets and dialogs leave the screen showing behind them, so
/// closing one of those does not count.
///
/// `RouteObserver` cannot tell these apart: the chat row menu is a
/// see-through `PageRouteBuilder`, so a page-only observer would fire for it.
class PageReturnObserver extends NavigatorObserver {
  final _listeners = <Route<dynamic>, VoidCallback>{};

  /// Calls [onReturn] each time an opaque page directly above [route] closes.
  void subscribe(Route<dynamic> route, VoidCallback onReturn) =>
      _listeners[route] = onReturn;

  void unsubscribe(Route<dynamic> route) => _listeners.remove(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is TransitionRoute && route.opaque && previousRoute != null) {
      _listeners[previousRoute]?.call();
    }
  }
}

/// The app's one instance, registered on the root navigator.
final pageReturnObserver = PageReturnObserver();
