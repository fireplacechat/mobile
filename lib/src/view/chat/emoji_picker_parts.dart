import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:fireplace/src/model/chat/emoji_catalog.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// The measured geometry of the emoji sheet, in logical pixels.
abstract final class EmojiPickerMetrics {
  /// Share of the screen the sheet covers before it is pulled up.
  static const double restingFraction = .541;
  static const double radius = 10;
  static const double edge = 16;
  static const double cell = 38;
  static const double rowGap = 10;
  static const double emoji = 28;
  static const double searchTop = 32;
  static const double searchHeight = 47;
  static const double headerBlock = 89.5;
  static const double sectionTitle = 41;
  static const double toolbarButton = 48;
  static const double toolbarGap = 4;
}

const emojiCategoryIcons = [
  CupertinoIcons.smiley,
  CupertinoIcons.paw,
  Icons.ramen_dining_outlined,
  Icons.sports_soccer_outlined,
  CupertinoIcons.car_detailed,
  CupertinoIcons.lightbulb,
  Icons.calculate_outlined,
  CupertinoIcons.flag,
];

class EmojiSearchHeader extends SliverPersistentHeaderDelegate {
  const EmojiSearchHeader({
    required this.color,
    required this.grown,
    required this.child,
  });
  final Color color;
  final double grown;
  final Widget child;
  @override
  double get minExtent => EmojiPickerMetrics.headerBlock + grown;
  @override
  double get maxExtent => EmojiPickerMetrics.headerBlock + grown;
  @override
  Widget build(BuildContext context, double shrink, bool overlaps) =>
      ColoredBox(
        color: color,
        child: Stack(
          children: [
            Positioned(
              top: 5,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  key: const Key('emojiPickerHandle'),
                  width: 36,
                  height: 5,
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: FireplaceUiTokens.of(context).secondaryText
                        .withValues(alpha: .7),
                  ),
                ),
              ),
            ),
            Positioned(
              top: EmojiPickerMetrics.searchTop,
              left: EmojiPickerMetrics.edge,
              right: EmojiPickerMetrics.edge,
              height: EmojiPickerMetrics.searchHeight + grown,
              child: child,
            ),
          ],
        ),
      );
  @override
  bool shouldRebuild(EmojiSearchHeader old) =>
      old.color != color || old.grown != grown || old.child != child;
}

class EmojiSearchField extends StatelessWidget {
  const EmojiSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide.none,
    );
    return TextField(
      key: const Key('emojiSearch'),
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      maxLength: emojiSearchLimit,
      textInputAction: TextInputAction.search,
      // The field keeps its measured height; long text scrolls inside it.
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(fontSize: 23, height: 1.2, color: t.text),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: 'Search',
        semanticCounterText: '',
        hintStyle: TextStyle(fontSize: 23, height: 1.2, color: t.secondaryText),
        filled: true,
        fillColor: t.separator,
        // With 23-point text at 1.2 line height this makes the 47-point field.
        contentPadding: const EdgeInsets.symmetric(vertical: 9.7),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 8, right: 6),
          child: Icon(CupertinoIcons.search, size: 24, color: t.secondaryText),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
      ),
    );
  }
}

class EmojiSectionTitle extends StatelessWidget {
  const EmojiSectionTitle({
    super.key,
    required this.name,
    required this.height,
  });
  final String name;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    alignment: AlignmentDirectional.bottomStart,
    padding: const EdgeInsets.fromLTRB(
      EmojiPickerMetrics.edge,
      0,
      EmojiPickerMetrics.edge,
      5,
    ),
    child: Semantics(
      header: true,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 17,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: FireplaceUiTokens.of(context).secondaryText,
        ),
      ),
    ),
  );
}

class EmojiGrid extends StatelessWidget {
  const EmojiGrid({
    super.key,
    required this.entries,
    required this.columns,
    required this.spacing,
    required this.keyPrefix,
    required this.onPicked,
  });
  final List<EmojiEntry> entries;
  final int columns;
  final double spacing;
  final String keyPrefix;
  final ValueChanged<String> onPicked;
  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: EmojiPickerMetrics.edge),
    sliver: SliverGrid.builder(
      itemCount: entries.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: EmojiPickerMetrics.cell,
        mainAxisSpacing: EmojiPickerMetrics.rowGap,
        crossAxisSpacing: spacing,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Semantics(
          button: true,
          label: entry.name,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('$keyPrefix-${entry.emoji}'),
            customBorder: const CircleBorder(),
            onTap: () => onPicked(entry.emoji),
            child: Center(
              child: Text(
                entry.emoji,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: EmojiPickerMetrics.emoji,
                  height: 1,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class EmojiCategoryToolbar extends StatelessWidget {
  const EmojiCategoryToolbar({
    super.key,
    required this.recents,
    required this.selected,
    required this.onSelected,
    required this.bottom,
  });
  final bool recents;
  final int selected;
  final ValueChanged<int> onSelected;
  final double bottom;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final labels = [
      if (recents) 'Recents',
      for (final category in emojiCategories) category.name,
    ];
    final icons = [if (recents) CupertinoIcons.clock, ...emojiCategoryIcons];
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ColoredBox(
          color: t.page.withValues(alpha: .86),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SizedBox(
              height:
                  EmojiPickerMetrics.toolbarButton +
                  2 * EmojiPickerMetrics.toolbarGap,
              child: ListView.separated(
                key: const Key('emojiCategories'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 2 * EmojiPickerMetrics.toolbarGap,
                  vertical: EmojiPickerMetrics.toolbarGap,
                ),
                itemCount: labels.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: EmojiPickerMetrics.toolbarGap),
                itemBuilder: (context, index) => IconButton(
                  key: ValueKey('emojiCategory-${labels[index]}'),
                  tooltip: labels[index],
                  isSelected: index == selected,
                  onPressed: () => onSelected(index),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(
                      EmojiPickerMetrics.toolbarButton,
                    ),
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: t.text.withValues(alpha: .8),
                    backgroundColor: index == selected
                        ? t.text.withValues(alpha: .14)
                        : Colors.transparent,
                  ),
                  icon: Icon(icons[index], size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
