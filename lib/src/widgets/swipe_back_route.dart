import 'package:flutter/cupertino.dart';

/// A page that slides in from the side and can be dragged back to the page
/// below, as on iOS: the page follows the finger and shows the page under
/// it, a short drag settles back, a longer or quicker one goes back (issue
/// 236).
///
/// iOS starts this drag only at the left edge. Android phones with gesture
/// navigation keep that edge for their own back gesture, so here the drag
/// may start anywhere on the page. Use it for pages without sideways
/// scrolling; a switch or slider still takes its own drag.
class SwipeBackPageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  SwipeBackPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => CupertinoPageTransition(
    primaryRouteAnimation: animation,
    secondaryRouteAnimation: secondaryAnimation,
    // Linear while dragging, so the page stays under the finger.
    linearTransition: popGestureInProgress,
    child: _SwipeBack(route: this, child: child),
  );

  _BackDrag _startDrag() => _BackDrag(
    navigator: navigator!,
    controller: controller!,
    isCurrent: () => isCurrent,
    isActive: () => isActive,
  );
}

// The same thresholds as the iOS back swipe in Flutter's Cupertino route.
const _minFlingVelocity = 1.0; // screen widths per second
const _settleDuration = Duration(milliseconds: 350);

/// One drag, in route-animation units: 1 is the page in place, 0 is gone.
class _BackDrag {
  _BackDrag({
    required this.navigator,
    required this.controller,
    required this.isCurrent,
    required this.isActive,
  }) {
    navigator.didStartUserGesture();
  }

  final NavigatorState navigator;
  final AnimationController controller;
  final ValueGetter<bool> isCurrent, isActive;

  void update(double fraction) => controller.value -= fraction;

  /// [velocity] is in screen widths per second, positive towards going back.
  void end(double velocity) {
    const curve = Curves.fastEaseInToSlowEaseOut;
    final bool stay;
    if (!isCurrent()) {
      stay = isActive(); // something else navigated meanwhile
    } else if (velocity.abs() >= _minFlingVelocity) {
      stay = velocity < 0;
    } else {
      stay = controller.value > 0.5;
    }
    if (stay) {
      controller.animateTo(1, duration: _settleDuration, curve: curve);
    } else {
      if (isCurrent()) navigator.pop();
      if (controller.isAnimating) {
        controller.animateBack(0, duration: _settleDuration, curve: curve);
      }
    }
    if (controller.isAnimating) {
      // Keep the gesture curve until the page has settled.
      late AnimationStatusListener done;
      done = (_) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(done);
      };
      controller.addStatusListener(done);
    } else {
      navigator.didStopUserGesture();
    }
  }
}

class _SwipeBack extends StatefulWidget {
  const _SwipeBack({required this.route, required this.child});
  final SwipeBackPageRoute<dynamic> route;
  final Widget child;

  @override
  State<_SwipeBack> createState() => _SwipeBackState();
}

class _SwipeBackState extends State<_SwipeBack> {
  _BackDrag? _drag;

  // Back is towards the reading end: right in left-to-right text.
  double get _direction =>
      Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  @override
  void dispose() {
    _finish(0);
    super.dispose();
  }

  void _finish(double velocity) {
    final drag = _drag;
    _drag = null;
    drag?.end(velocity);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) {
      if (widget.route.popGestureEnabled) _drag = widget.route._startDrag();
    },
    onHorizontalDragUpdate: (d) => _drag?.update(
      _direction * d.primaryDelta! / MediaQuery.sizeOf(context).width,
    ),
    onHorizontalDragEnd: (d) => _finish(
      _direction *
          d.velocity.pixelsPerSecond.dx /
          MediaQuery.sizeOf(context).width,
    ),
    onHorizontalDragCancel: () => _finish(0),
    child: widget.child,
  );
}
