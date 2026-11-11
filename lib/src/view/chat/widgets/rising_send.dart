import 'package:flutter/material.dart';

/// Slides a just-sent message up into its place. The conversation list clips
/// the start of the move, so the bubble comes up from behind the composer
/// and the keyboard. Only the in-flight row uses this. The saved history row
/// that replaces it does not play the move again.
class RisingSend extends StatefulWidget {
  const RisingSend({required this.child, super.key});

  final Widget child;

  /// Short enough to feel immediate, long enough to read as a slide.
  static const duration = Duration(milliseconds: 180);

  @override
  State<RisingSend> createState() => _RisingSendState();
}

class _RisingSendState extends State<RisingSend>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: RisingSend.duration,
  )..forward();

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SlideTransition(position: _offset, child: widget.child);
}
