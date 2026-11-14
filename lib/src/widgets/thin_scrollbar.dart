import 'package:flutter/cupertino.dart';

/// The app's scroll bar: a thin, rounded thumb at the trailing edge that
/// shows while the list moves and fades when it stops, on both platforms.
///
/// It is painted over the list, so it takes no width. It follows the content
/// through the elastic overscroll, and it can be dragged after a long press.
///
/// Give it the list's [controller] when the list has one; a list without one
/// is found through the page's primary scroll controller.
class ThinScrollbar extends StatelessWidget {
  const ThinScrollbar({super.key, required this.child, this.controller});
  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) =>
      CupertinoScrollbar(controller: controller, child: child);
}
