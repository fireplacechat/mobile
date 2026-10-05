import 'package:flutter/material.dart';

/// Brand colour of the mark: burnt orange #BF5700.
const fireplaceOrange = Color(0xFFBF5700);

/// The Fireplace mark: two flat flames (the "Gather" symbol), drawn from the same curve
/// data as `vectors/fireplace-symbol-master.svg` so it stays sharp at any size.
///
/// Brand rule: the flame stays burnt orange in both themes.
/// The mark is fitted to its own bounds, so [size] is (nearly) the height of the flames.
class FireplaceLogo extends StatelessWidget {
  const FireplaceLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'fireplace.',
      image: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: const FlamePainter(fireplaceOrange),
        ),
      ),
    );
  }
}

/// Paints the two flames.
class FlamePainter extends CustomPainter {
  const FlamePainter(this.color, {this.fitToBounds = true});
  final Color color;

  /// True: scale the flames' own bounding box to fill the canvas height (UI use).
  /// False: draw the 1024 master viewBox as-is, margins included (icon artwork).
  final bool fitToBounds;

  // Curve data from the approved master, in its pre-transform coordinates.
  static const _paths = <String>[
    'M388 183 C470 225 519 303 495 393 C474 472 404 522 361 587 C312 662 325 750 419 809 '
        'C294 805 204 762 178 667 C147 555 208 478 295 405 C366 345 415 292 388 183 Z',
    'M585 377 C563 433 588 476 631 521 C683 575 711 617 693 677 C670 758 577 807 445 809 '
        'C501 777 527 732 521 677 C516 629 479 586 475 539 C466 467 510 415 585 377 Z',
  ];

  // The master wraps them in translate(-53 -132) scale(1.3) inside a 1024 viewBox.
  static const _scale = 1.3, _dx = -53.0, _dy = -132.0;

  /// The mark in master (1024) coordinates.
  static Path master() {
    final path = Path();
    for (final d in _paths) {
      path.addPath(_parse(d), Offset.zero);
    }
    return path
        .transform(Matrix4.diagonal3Values(_scale, _scale, 1).storage)
        .shift(const Offset(_dx, _dy));
  }

  static Rect? _tight;

  /// The visible extent of the mark in master coordinates. `Path.getBounds` includes curve
  /// control points and is wider than the shape, so measure along the curves instead.
  static Rect tightBounds() => _tight ??= () {
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final m in master().computeMetrics()) {
      for (var d = 0.0; d <= m.length; d += 0.5) {
        final o = m.getTangentForOffset(d)!.position;
        if (o.dx < l) l = o.dx;
        if (o.dx > r) r = o.dx;
        if (o.dy < t) t = o.dy;
        if (o.dy > b) b = o.dy;
      }
    }
    return Rect.fromLTRB(l, t, r, b);
  }();

  static Path _parse(String d) => parseSvgPath(d);

  @override
  void paint(Canvas canvas, Size s) {
    final path = master();
    final b = tightBounds();
    final k = fitToBounds ? s.height / b.height : s.width / 1024;
    canvas.save();
    if (fitToBounds) {
      canvas.translate((s.width - b.width * k) / 2 - b.left * k, -b.top * k);
    }
    canvas.scale(k);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(FlamePainter old) =>
      old.color != color || old.fitToBounds != fitToBounds;
}

/// Parses SVG path data made of absolute M, L, H, V, C, Q and Z commands (the subset used by
/// our brand artwork). Commands and numbers may touch ("M388 183"); a command may be followed
/// by several coordinate sets.
Path parseSvgPath(String d) {
  final t = RegExp(r'[MLHVCQZ]|-?\d+(?:\.\d+)?')
      .allMatches(d)
      .map((m) => m[0]!)
      .toList();
  final p = Path();
  var i = 0;
  double n() => double.parse(t[i++]);
  bool more() => i < t.length && double.tryParse(t[i]) != null;
  var x = 0.0, y = 0.0;
  while (i < t.length) {
    switch (t[i++]) {
      case 'M':
        x = n();
        y = n();
        p.moveTo(x, y);
        while (more()) {
          x = n();
          y = n();
          p.lineTo(x, y); // extra pairs after M are implicit lineTo
        }
      case 'L':
        while (more()) {
          x = n();
          y = n();
          p.lineTo(x, y);
        }
      case 'H':
        while (more()) {
          x = n();
          p.lineTo(x, y);
        }
      case 'V':
        while (more()) {
          y = n();
          p.lineTo(x, y);
        }
      case 'C':
        while (more()) {
          final x1 = n(), y1 = n(), x2 = n(), y2 = n();
          x = n();
          y = n();
          p.cubicTo(x1, y1, x2, y2, x, y);
        }
      case 'Q':
        while (more()) {
          final x1 = n(), y1 = n();
          x = n();
          y = n();
          p.quadraticBezierTo(x1, y1, x, y);
        }
      case 'Z':
        p.close();
    }
  }
  return p;
}
