import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// The search pill above the conversation list. At rest it shows a centred
/// "Search"; once focused or filled it becomes an ordinary field with a thin
/// outline in the accent colour.
class ChatSearchField extends StatefulWidget {
  const ChatSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<ChatSearchField> createState() => _ChatSearchFieldState();
}

class _ChatSearchFieldState extends State<ChatSearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(ChatSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final filled = widget.controller.text.isNotEmpty;
    final active = _focus.hasFocus || filled;
    const style = TextStyle(fontSize: 16, height: 1.25);
    final hintStyle = style.copyWith(color: t.secondaryText);
    final line = MediaQuery.textScalerOf(context).scale(16) * 1.25;
    final icon = Icon(Icons.search, size: line, color: t.secondaryText);
    OutlineInputBorder pill(BorderSide side) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: side,
    );
    return TextField(
      key: const Key('chatSearch'),
      controller: widget.controller,
      focusNode: _focus,
      style: style,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        // Forty-eight points tall at the default text size, so it stays an
        // easy target; larger text grows it.
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: math.max(8, (48 - line) / 2),
        ),
        hintText: active ? 'Search' : null,
        hintStyle: hintStyle,
        hint: active
            ? null
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Search',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hintStyle,
                    ),
                  ),
                ],
              ),
        prefixIcon: active ? icon : null,
        prefixIconConstraints: const BoxConstraints(minWidth: 44),
        suffixIcon: filled
            ? IconButton(
                key: const Key('clearChatSearch'),
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged('');
                },
              )
            : null,
        border: pill(BorderSide.none),
        enabledBorder: pill(BorderSide.none),
        focusedBorder: pill(BorderSide(color: t.accent)),
      ),
      onChanged: widget.onChanged,
    );
  }
}
