import 'package:flutter/material.dart';

import 'logo.dart';
import 'lockup_data.dart';
import 'design_tokens.dart';

/// The Fireplace lockup (flame above "fireplace.") exactly as laid out in the cream phone
/// wallpaper of the art pack. The native launch screens use the same artwork, so the hand-off
/// from the system splash to this one does not move or resize anything.
class FireplaceLockup extends StatelessWidget {
  const FireplaceLockup({
    super.key,
    this.width = lockupLogicalWidth,
    this.wordmarkColor,
  });
  final double width;

  /// Colour of the letters (the flame and the full stop stay orange). Null keeps the approved cream
  /// version's dark ink; the dark theme passes the approved light ink.
  final Color? wordmarkColor;

  static double heightFor(double width) =>
      width * lockupViewBox.h / lockupViewBox.w;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'fireplace.',
    image: true,
    child: ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, heightFor(width)),
        painter: LockupPainter(wordmarkColor: wordmarkColor),
      ),
    ),
  );
}

/// Width, in logical pixels, of the lockup on the native launch screens.
const lockupLogicalWidth = 200.0;

/// Brand cream (#FAF7F0): the loading screen's background in the light theme.
const fireplaceCream = Color(0xFFFAF7F0);

/// Charcoal (#333F48): the loading screen's background in the dark theme, the corner colour of the approved
/// orange-on-charcoal wallpaper. The Android and iOS dark launch screens use the same value.
const fireplaceCharcoal = Color(0xFF333F48);

/// The approved lettering colour on charcoal (white, as in the approved dark wallpaper).
const fireplaceWordmarkOnCharcoal = Color(0xFFFFFFFF);

/// The approved lowercase lettering and orange dot, using the artwork's outlines.
class FireplaceWordmark extends StatelessWidget {
  const FireplaceWordmark({super.key, this.height = 32});
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final bounds = WordmarkPainter.bounds;
      final width = (height * bounds.width / bounds.height).clamp(
        0.0,
        box.maxWidth,
      );
      return Semantics(
        label: 'fireplace.',
        image: true,
        child: ExcludeSemantics(
          child: CustomPaint(
            size: Size(width, width * bounds.height / bounds.width),
            painter: WordmarkPainter(
              Theme.of(context).brightness == Brightness.dark
                  ? fireplaceWordmarkOnCharcoal
                  : const Color(LockupPainter._ink),
            ),
          ),
        ),
      );
    },
  );
}

class WordmarkPainter extends CustomPainter {
  const WordmarkPainter(this.letterColor);
  final Color letterColor;
  static final Rect bounds = LockupPainter._glyphs
      .map((glyph) => glyph.$2.getBounds())
      .reduce((a, b) => a.expandToInclude(b));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / bounds.width);
    canvas.translate(-bounds.left, -bounds.top);
    for (final (color, path) in LockupPainter._glyphs) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.toARGB32() == LockupPainter._ink ? letterColor : color
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(WordmarkPainter old) => old.letterColor != letterColor;
}

/// Explanatory copy can include the same vector wordmark without substituting a font.
class FireplaceBrandText extends StatelessWidget {
  const FireplaceBrandText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  static final _brand = RegExp(r'\bFireplace\b\.?', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    if (!_brand.hasMatch(text)) {
      return Text(text, style: style, textAlign: textAlign);
    }
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _brand.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: FireplaceWordmark(
            height: MediaQuery.textScalerOf(context)
                .scale(effective.fontSize ?? 14),
          ),
        ),
      );
      start = match.end;
    }
    spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      textAlign: textAlign,
      semanticsLabel: text.replaceAll(_brand, 'fireplace.'),
    );
  }
}

class LockupPainter extends CustomPainter {
  const LockupPainter({this.wordmarkColor});
  final Color? wordmarkColor;

  /// The letters of the cream version are drawn in this ink colour (the full stop is orange).
  static const _ink = 0xFF292E25;

  static final List<(Color, Path)> _glyphs = [
    for (final (color, x, y, scale, d) in lockupGlyphs)
      (
        Color(color),
        parseSvgPath(d)
            .transform(Matrix4.diagonal3Values(scale, -scale, 1).storage)
            .shift(Offset(x, y)),
      ),
  ];

  static final Path _flame = FlamePainter.master()
      .transform(
        Matrix4.diagonal3Values(
          lockupFlame.scale,
          lockupFlame.scale,
          1,
        ).storage,
      )
      .shift(Offset(lockupFlame.x, lockupFlame.y));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / lockupViewBox.w);
    canvas.translate(-lockupViewBox.x.toDouble(), -lockupViewBox.y.toDouble());
    canvas.drawPath(
      _flame,
      Paint()
        ..color = fireplaceOrange
        ..isAntiAlias = true,
    );
    for (final (color, path) in _glyphs) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.toARGB32() == _ink ? (wordmarkColor ?? color) : color
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(LockupPainter old) => old.wordmarkColor != wordmarkColor;
}

/// The startup screen: the approved lockup on cream (light) or charcoal (dark), placed exactly like the
/// native launch screens. Normal loading shows only the logo; startup failures retain a scrollable
/// status card so explanations and recovery buttons stay reachable on short screens.
class FireplaceSplash extends StatelessWidget {
  const FireplaceSplash({
    super.key,
    this.message,
    this.actions = const [],
    this.title = 'Opening Fireplace',
  });
  final String? message;
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens =
        Theme.of(context).extension<FireplaceUiTokens>() ??
        (dark ? FireplaceUiTokens.dark : FireplaceUiTokens.light);
    return Scaffold(
      backgroundColor: dark ? fireplaceCharcoal : fireplaceCream,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Match the centered native lockup on iOS and Android <= 11. Android 12+
          // shows a system flame-only splash. These outlines come from the approved
          // wallpaper artwork, without decoding or caching its roughly 17 MiB bitmap.
          Semantics(
            label: actions.isEmpty ? 'Loading fireplace.' : null,
            child: Center(
              child: FireplaceLockup(
                wordmarkColor: dark ? fireplaceWordmarkOnCharcoal : null,
              ),
            ),
          ),
          if (actions.isNotEmpty)
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) => Align(
                  alignment:
                      box.maxHeight < 600 &&
                          box.maxWidth / 2 - lockupLogicalWidth / 2 - 40 >= 240
                      ? Alignment.centerRight
                      : Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            box.maxHeight < 600 &&
                                box.maxWidth / 2 -
                                        lockupLogicalWidth / 2 -
                                        40 >=
                                    240
                            ? box.maxWidth / 2 - lockupLogicalWidth / 2 - 40
                            : 440,
                        maxHeight:
                            (box.maxHeight * (box.maxHeight < 600 ? .75 : .28))
                                .clamp(0, double.infinity),
                      ),
                      child: Card(
                        color: tokens.panel,
                        child: SingleChildScrollView(
                          key: const Key('splashScroll'),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                liveRegion: true,
                                child: FireplaceBrandText(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(color: tokens.text),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                message ?? 'Loading your account…',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: tokens.secondaryText),
                              ),
                              const SizedBox(height: 16),
                              ...actions,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
