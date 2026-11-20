import 'package:flutter/material.dart';

import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/settings/settings_icon.dart';

/// A Settings page with a large title that scrolls away under the bar, where
/// a small copy of it then fades in.
///
/// The large title is part of the list rather than a fixed-height header, so
/// it wraps instead of clipping on a narrow phone with large text. [body]
/// replaces the list (a loading or error state); the bar then shows the
/// title at once.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.title,
    this.children = const [],
    this.body,
  });

  final String title;
  final List<Widget> children;
  final Widget? body;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _scroll = ScrollController();
  final _largeTitle = GlobalKey();
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _update() {
    final height = _largeTitle.currentContext?.size?.height ?? 40;
    // Collapsed once most of the large title has gone under the bar.
    final collapsed = _scroll.offset > height * .6;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final showSmall = widget.body != null || _collapsed;
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        title: ExcludeSemantics(
          excluding: !showSmall,
          child: AnimatedOpacity(
            opacity: showSmall ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            child: Text(widget.title),
          ),
        ),
      ),
      body:
          widget.body ??
          UiPageScroll(
            controller: _scroll,
            padding: SettingsIcon.hiddenAt(context)
                ? const EdgeInsets.fromLTRB(12, 0, 12, 32)
                : const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Padding(
                key: _largeTitle,
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
                child: Semantics(
                  header: true,
                  child: Text(
                    widget.title,
                    // Grows with the text size, but only so far that a long
                    // word still fits on a narrow phone; the bar's copy of
                    // the title scales as usual.
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.35),
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(fontSize: 32, letterSpacing: -.5),
                  ),
                ),
              ),
              ...widget.children,
            ],
          ),
    );
  }
}
