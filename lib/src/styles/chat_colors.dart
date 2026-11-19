import 'package:flutter/material.dart';

/// Presentation only: no account fields and no cloud writes.
enum ChatBubbleColor {
  ember(
    'Ember',
    Color(0xFFBF5700),
    Color(0xFFF7C9A5),
    Color(0xFF673000),
    Color(0xFFA94B00),
    Color(0xFFE8914A),
  ),
  forest(
    'Forest',
    Color(0xFF28634F),
    Color(0xFFB9DEC6),
    Color(0xFF044E36),
    Color(0xFF28634F),
    Color(0xFF94B1A7),
  ),
  ocean(
    'Ocean',
    Color(0xFF285D83),
    Color(0xFFBBD9F0),
    Color(0xFF004773),
    Color(0xFF285D83),
    Color(0xFF94AEC1),
  ),
  plum(
    'Plum',
    Color(0xFF734A78),
    Color(0xFFE8C5E8),
    Color(0xFF592F63),
    Color(0xFF734A78),
    Color(0xFFB9A4BC),
  ),
  stone(
    'Stone',
    Color(0xFF59534C),
    Color(0xFFE0D5C3),
    Color(0xFF345061),
    Color(0xFF59534C),
    Color(0xFFACA9A6),
  ),
  // Nine more, chosen by the owner on 2026-11-16. New ones go at the end:
  // a colour's name is what is saved and published, never its place.
  clay(
    'Clay',
    Color(0xFFA65345),
    Color(0xFFF3C7B6),
    Color(0xFF6B3127),
    Color(0xFFA65345),
    Color(0xFFD9A294),
  ),
  rose(
    'Rose',
    Color(0xFF965773),
    Color(0xFFEEC6DB),
    Color(0xFF642F51),
    Color(0xFF965773),
    Color(0xFFD4A6BB),
  ),
  berry(
    'Berry',
    Color(0xFF843F50),
    Color(0xFFEFC1CE),
    Color(0xFF672340),
    Color(0xFF843F50),
    Color(0xFFD29AA8),
  ),
  honey(
    'Honey',
    Color(0xFF86631F),
    Color(0xFFECD392),
    Color(0xFF584200),
    Color(0xFF86631F),
    Color(0xFFD2B77A),
  ),
  olive(
    'Olive',
    Color(0xFF66713E),
    Color(0xFFD3DBA1),
    Color(0xFF3F4C11),
    Color(0xFF66713E),
    Color(0xFFB9C294),
  ),
  lagoon(
    'Lagoon',
    Color(0xFF2C716F),
    Color(0xFFAEDFD7),
    Color(0xFF00504E),
    Color(0xFF2C716F),
    Color(0xFF8FBDB7),
  ),
  smoke(
    'Smoke',
    Color(0xFF536B7A),
    Color(0xFFC3D8E4),
    Color(0xFF294B61),
    Color(0xFF536B7A),
    Color(0xFFA3B8C4),
  ),
  grape(
    'Grape',
    Color(0xFF75608E),
    Color(0xFFDDCBF1),
    Color(0xFF4F336F),
    Color(0xFF75608E),
    Color(0xFFBEB0D3),
  ),
  cocoa(
    'Cocoa',
    Color(0xFF765342),
    Color(0xFFE7CCB4),
    Color(0xFF593827),
    Color(0xFF765342),
    Color(0xFFC8AE9A),
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

  /// The colours as they are offered: round the colour wheel, three to a
  /// row, from the warm ones through pinks and purples, blues and greens,
  /// to the earthy and neutral ones. Separate from the order above, which
  /// only ever grows at the end.
  static const List<ChatBubbleColor> offered = [
    ember, clay, berry, //
    rose, plum, grape, //
    ocean, smoke, lagoon, //
    forest, olive, honey, //
    cocoa, stone,
  ];

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
  /// a pin). Between the two bubble colours, nearer the sender's, and faded
  /// into [page], so it
  /// stands apart from both bubbles and from the page whichever two colours
  /// are chosen, also when both are the same (test/styles/chat_colors_test).
  /// In dark mode the outgoing colour's lighter accent stands in for its
  /// fill, which is too close to some dark incoming fills. In light mode it
  /// leans further to the sender's fill, since the incoming tints are deep
  /// enough to sit close to a half-way mix.
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
        : Color.lerp(theirs, outgoing.outgoing, .85)!;
    return Color.lerp(page, between, dark ? .7 : .6)!;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatBubbleColors && other.outgoing == outgoing;
  @override
  int get hashCode => outgoing.hashCode;
}
