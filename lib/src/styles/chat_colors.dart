import 'package:flutter/material.dart';

/// Presentation only: no account fields and no cloud writes.
enum ChatBubbleColor {
  ember(
    'Ember',
    Color(0xFFBF5700),
    Color(0xFFF5E5D9),
    Color(0xFF50311D),
    Color(0xFFA94B00),
    Color(0xFFE8914A),
  ),
  forest(
    'Forest',
    Color(0xFF28634F),
    Color(0xFFE0ECE4),
    Color(0xFF293F35),
    Color(0xFF28634F),
    Color(0xFF94B1A7),
  ),
  ocean(
    'Ocean',
    Color(0xFF285D83),
    Color(0xFFE1EBF3),
    Color(0xFF293E50),
    Color(0xFF285D83),
    Color(0xFF94AEC1),
  ),
  plum(
    'Plum',
    Color(0xFF734A78),
    Color(0xFFEFE3EF),
    Color(0xFF453449),
    Color(0xFF734A78),
    Color(0xFFB9A4BC),
  ),
  stone(
    'Stone',
    Color(0xFF59534C),
    Color(0xFFEFEBE5),
    Color(0xFF3B464D),
    Color(0xFF59534C),
    Color(0xFFACA9A6),
  );

  const ChatBubbleColor(
    this.label,
    this.outgoing,
    this.lightIncoming,
    this.darkIncoming,
    this.lightText,
    this.darkText,
  );
  final String label;
  final Color outgoing, lightIncoming, darkIncoming;

  /// The colour as small text and links: the fill itself is too dim for
  /// that on a dark page, and ember is too light for it on cream.
  final Color lightText, darkText;
  Color accentText(Brightness brightness) =>
      brightness == Brightness.dark ? darkText : lightText;
  Color incoming(Brightness brightness) =>
      brightness == Brightness.dark ? darkIncoming : lightIncoming;
}

/// This account's one chat colour (decision 0052). Its own messages use it,
/// and so do other people's phones for this account's messages. Each other
/// person's messages use the soft tint of *their* colour.
@immutable
class ChatBubbleColors {
  const ChatBubbleColors({this.outgoing = ChatBubbleColor.ember});
  final ChatBubbleColor outgoing;

  /// What someone else's messages use until their own colour has arrived.
  static const ChatBubbleColor unknown = ChatBubbleColor.stone;

  /// The colour of other people's messages where no one person is meant.
  ChatBubbleColor get incoming => unknown;

  /// The saved form: the colour's name. Anything unknown reads as the
  /// default. An older save also named a second colour, for other people's
  /// messages; it is ignored.
  String get stored => outgoing.name;
  factory ChatBubbleColors.parse(String stored) => ChatBubbleColors(
    outgoing:
        ChatBubbleColor.values.asNameMap()[stored.split(',').first] ??
        ChatBubbleColor.ember,
  );

  /// The tint behind a message after a jump to it (a search result, a quote,
  /// a pin). Between the two bubble colours and faded into [page], so it
  /// stands apart from both bubbles and from the page whichever two colours
  /// are chosen, also when both are the same (test/styles/chat_colors_test).
  /// In dark mode the outgoing colour's lighter accent stands in for its
  /// fill, which is too close to some dark incoming fills.
  ///
  /// [other] is the colour of the other person's messages in that chat.
  Color jumpHighlight(
    Brightness brightness,
    Color page, {
    ChatBubbleColor other = unknown,
  }) {
    final theirs = other.incoming(brightness);
    final dark = brightness == Brightness.dark;
    final between = dark
        ? Color.lerp(theirs, outgoing.accentText(brightness), .9)!
        : Color.lerp(theirs, outgoing.outgoing, .5)!;
    return Color.lerp(page, between, dark ? .7 : .5)!;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatBubbleColors && other.outgoing == outgoing;
  @override
  int get hashCode => outgoing.hashCode;
}
