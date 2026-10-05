import 'package:flutter/material.dart';

@immutable
class FireplaceUiTokens extends ThemeExtension<FireplaceUiTokens> {
  const FireplaceUiTokens({
    required this.page,
    required this.panel,
    required this.text,
    required this.secondaryText,
    required this.accent,
    required this.accentText,
    required this.selectedRow,
    required this.incomingBubble,
    required this.incomingText,
    required this.outgoingBubble,
    required this.outgoingText,
    required this.separator,
    required this.warningSurface,
    required this.warningText,
    required this.danger,
  });
  final Color page;
  final Color panel;
  final Color text;
  final Color secondaryText;
  final Color accent;

  /// Orange for small text and links (the brand accent itself is too light for that on cream).
  final Color accentText;
  final Color selectedRow;
  final Color incomingBubble;
  final Color incomingText;
  final Color outgoingBubble;
  final Color outgoingText;
  final Color separator;
  final Color warningSurface;
  final Color warningText;
  final Color danger;
  static const light = FireplaceUiTokens(
    page: Color(0xFFFAF7F0),
    panel: Color(0xFFFFFFFF),
    text: Color(0xFF27231F),
    secondaryText: Color(0xFF62584F),
    accent: Color(0xFFBF5700), // brand burnt orange; white on it is 4.59:1
    accentText: Color(0xFFA94B00),
    selectedRow: Color(0xFFF1EBE3),
    incomingBubble: Color(0xFFEFEBE5),
    incomingText: Color(0xFF403B36),
    outgoingBubble: Color(0xFFBF5700),
    outgoingText: Color(0xFFFFFFFF),
    separator: Color(0xFFE9E3DB),
    warningSurface: Color(0xFFFFF0CC),
    warningText: Color(0xFF684A0A),
    danger: Color(0xFFA92B2B),
  );
  static const dark = FireplaceUiTokens(
    page: Color(0xFF252D33),
    panel: Color(0xFF2D373F),
    text: Color(0xFFF4F3EF),
    secondaryText: Color(0xFFBCC6CC),
    accent: Color(0xFFBF5700),
    accentText: Color(0xFFE8914A),
    selectedRow: Color(0xFF35424B),
    incomingBubble: Color(0xFF3B464D),
    incomingText: Color(0xFFFFF8EE),
    outgoingBubble: Color(0xFFBF5700),
    outgoingText: Color(0xFFFFFFFF),
    separator: Color(0xFF43515A),
    warningSurface: Color(0xFF45371D),
    warningText: Color(0xFFFFE3A4),
    danger: Color(0xFFFFAAA5),
  );
  static FireplaceUiTokens of(BuildContext context) =>
      Theme.of(context).extension<FireplaceUiTokens>()!;
  @override
  FireplaceUiTokens copyWith({
    Color? page,
    Color? panel,
    Color? text,
    Color? secondaryText,
    Color? accent,
    Color? accentText,
    Color? selectedRow,
    Color? incomingBubble,
    Color? incomingText,
    Color? outgoingBubble,
    Color? outgoingText,
    Color? separator,
    Color? warningSurface,
    Color? warningText,
    Color? danger,
  }) => FireplaceUiTokens(
    page: page ?? this.page,
    panel: panel ?? this.panel,
    text: text ?? this.text,
    secondaryText: secondaryText ?? this.secondaryText,
    accent: accent ?? this.accent,
    accentText: accentText ?? this.accentText,
    selectedRow: selectedRow ?? this.selectedRow,
    incomingBubble: incomingBubble ?? this.incomingBubble,
    incomingText: incomingText ?? this.incomingText,
    outgoingBubble: outgoingBubble ?? this.outgoingBubble,
    outgoingText: outgoingText ?? this.outgoingText,
    separator: separator ?? this.separator,
    warningSurface: warningSurface ?? this.warningSurface,
    warningText: warningText ?? this.warningText,
    danger: danger ?? this.danger,
  );
  @override
  FireplaceUiTokens lerp(covariant FireplaceUiTokens? other, double t) {
    if (other == null) return this;
    return FireplaceUiTokens(
      page: Color.lerp(page, other.page, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      text: Color.lerp(text, other.text, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      selectedRow: Color.lerp(selectedRow, other.selectedRow, t)!,
      incomingBubble: Color.lerp(incomingBubble, other.incomingBubble, t)!,
      incomingText: Color.lerp(incomingText, other.incomingText, t)!,
      outgoingBubble: Color.lerp(outgoingBubble, other.outgoingBubble, t)!,
      outgoingText: Color.lerp(outgoingText, other.outgoingText, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
