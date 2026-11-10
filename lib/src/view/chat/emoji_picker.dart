import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/model/chat/emoji_catalog.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/emoji_picker_parts.dart';

export 'package:fireplace/src/view/chat/emoji_picker_parts.dart'
    show EmojiPickerMetrics;

/// Every emoji, by category, with a search that never leaves the device.
/// It rests at about half the screen, pulls up to full height, and closes
/// when dragged down.
class EmojiPickerSheet extends StatefulWidget {
  const EmojiPickerSheet({
    super.key,
    required this.onPicked,
    required this.onDismissed,
    this.recent = const [],
  });
  final ValueChanged<String> onPicked;
  final VoidCallback onDismissed;

  /// Emoji this person reacted with before, newest first.
  final List<String> recent;
  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  final _sheet = DraggableScrollableController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  ScrollController? _scroll;
  List<double> _offsets = const [];
  int _section = 0;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocus);
  }

  @override
  void dispose() {
    _scroll?.removeListener(_onScroll);
    _searchFocus
      ..removeListener(_onSearchFocus)
      ..dispose();
    _search.dispose();
    _sheet.dispose();
    super.dispose();
  }

  // Typing needs room above the keyboard, so searching opens the sheet fully.
  void _onSearchFocus() {
    if (_searchFocus.hasFocus) _expand();
  }

  void _expand() {
    if (!_sheet.isAttached) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheet.jumpTo(1);
    } else {
      _sheet.animateTo(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onScroll() {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients || _offsets.isEmpty) return;
    var section = 0;
    for (var i = 0; i < _offsets.length; i++) {
      if (scroll.offset + 1 >= _offsets[i]) section = i;
    }
    if (section != _section) setState(() => _section = section);
  }

  void _attach(ScrollController controller) {
    if (identical(_scroll, controller)) return;
    _scroll?.removeListener(_onScroll);
    _scroll = controller..addListener(_onScroll);
  }

  void _jump(int section) {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    scroll.jumpTo(math.min(_offsets[section], scroll.position.maxScrollExtent));
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final t = FireplaceUiTokens.of(context);
    final query = _search.text.trim();
    final searching = query.isNotEmpty;
    final results = searching ? _results(query) : const <EmojiEntry>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = math.max(
          1,
          width ~/ (EmojiPickerMetrics.cell + EmojiPickerMetrics.rowGap),
        );
        final spacing = columns == 1
            ? 0.0
            : (width - 2 * EmojiPickerMetrics.edge - columns * 38) /
                  (columns - 1);
        final title =
            EmojiPickerMetrics.sectionTitle -
            17 * 1.2 +
            media.textScaler.scale(17) * 1.2;
        // Text grows the search field and the block that holds it.
        final grown = (media.textScaler.scale(23) - 23) * 1.2;
        final recent = widget.recent.take(columns).toList();
        final sections = <(String, List<EmojiEntry>)>[
          if (recent.isNotEmpty)
            ('Recents', [for (final e in recent) EmojiEntry(e, e, const [])]),
          for (final c in emojiCategories) (c.name, c.entries),
        ];
        final offsets = <double>[];
        var at = 0.0;
        for (final (_, entries) in sections) {
          offsets.add(at);
          final rows = (entries.length / columns).ceil();
          at +=
              title +
              rows * EmojiPickerMetrics.cell +
              (rows - 1) * EmojiPickerMetrics.rowGap;
        }
        _offsets = offsets;
        final toolbar =
            EmojiPickerMetrics.toolbarButton +
            2 * EmojiPickerMetrics.toolbarGap;
        final below = searching
            ? media.padding.bottom + 16
            : toolbar + 8 + media.padding.bottom;
        final top =
            (constraints.maxHeight - media.padding.top - 10) /
            constraints.maxHeight;
        final resting = math.min(EmojiPickerMetrics.restingFraction, top);
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            if (notification.extent <= .02 && !_closed) {
              _closed = true;
              widget.onDismissed();
            }
            return false;
          },
          child: DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: resting,
            minChildSize: 0,
            maxChildSize: top,
            snap: true,
            snapSizes: [resting],
            builder: (context, scroll) {
              _attach(scroll);
              return Material(
                key: const Key('emojiPicker'),
                color: t.panel,
                elevation: 16,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(EmojiPickerMetrics.radius),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    CustomScrollView(
                      controller: scroll,
                      slivers: [
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: EmojiSearchHeader(
                            color: t.panel,
                            grown: grown,
                            child: EmojiSearchField(
                              controller: _search,
                              focusNode: _searchFocus,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        if (searching && results.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(EmojiPickerMetrics.edge),
                              child: Text(
                                'No emoji found',
                                key: Key('emojiSearchEmpty'),
                              ),
                            ),
                          ),
                        if (searching && results.isNotEmpty)
                          EmojiGrid(
                            entries: results,
                            columns: columns,
                            spacing: spacing,
                            keyPrefix: 'pickReaction',
                            onPicked: widget.onPicked,
                          ),
                        if (!searching)
                          for (final (index, (name, entries))
                              in sections.indexed) ...[
                            SliverToBoxAdapter(
                              child: EmojiSectionTitle(
                                name: name,
                                height: title,
                              ),
                            ),
                            EmojiGrid(
                              entries: entries,
                              columns: columns,
                              spacing: spacing,
                              keyPrefix: index == 0 && recent.isNotEmpty
                                  ? 'recentReaction'
                                  : 'pickReaction',
                              onPicked: widget.onPicked,
                            ),
                          ],
                        SliverToBoxAdapter(child: SizedBox(height: below)),
                      ],
                    ),
                    if (!searching)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: EmojiCategoryToolbar(
                          recents: recent.isNotEmpty,
                          selected: _section,
                          onSelected: _jump,
                          bottom: media.padding.bottom + 8,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<EmojiEntry> _results(String query) {
    final found = searchEmoji(query);
    // An emoji typed from the keyboard is offered as it is.
    if (validReactionEmoji(query) && found.every((e) => e.emoji != query)) {
      return [EmojiEntry(query, query, const []), ...found];
    }
    return found;
  }
}
