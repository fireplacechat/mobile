import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// Keep chat/search controls scroll-reachable when a keyboard leaves little space.
class UiBodyViewport extends StatelessWidget {
  const UiBodyViewport({
    super.key,
    required this.child,
    this.anchorBottom = false,
  });
  final Widget child;
  final bool anchorBottom;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxHeight >= 280) return child;
      return SingleChildScrollView(
        reverse: anchorBottom,
        child: SizedBox(
          height: math.max(
            480,
            MediaQuery.textScalerOf(context).scale(16) * 16,
          ),
          child: child,
        ),
      );
    },
  );
}

/// Constrained scrolling body for forms/settings, not the message timeline.
class UiPageScroll extends StatelessWidget {
  const UiPageScroll({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(20),
    this.maxWidth = 600,
    this.controller,
  });
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          controller: controller,
          padding: padding,
          children: children,
        ),
      ),
    ),
  );
}

class UiEmptyState extends StatelessWidget {
  const UiEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.chat_bubble_outline_rounded,
  });
  final String title, message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: FireplaceUiTokens.of(context).selectedRow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              icon,
              size: 36,
              color: FireplaceUiTokens.of(context).accentText,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}
