import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Every look-and-feel choice for the loading-screen fireflies. Tune these
/// first; the drawing code below only follows them.
///
/// To see changes without a phone, render a clip and open
/// `build/previews/fireflies/index.html` in a browser:
/// `flutter test scripts/preview/fireflies_frames_test.dart`.
/// With a phone or emulator, hot reload works too:
/// `flutter run -t scripts/preview/fireflies_preview.dart`.
@immutable
class FireflyStyle {
  const FireflyStyle({
    required this.color,
    this.coreColor,
    this.count = 14,
    this.glowRadius = 14,
    this.coreRadius = 1.6,
    this.wander = 18,
    this.wanderPeriod = const Duration(seconds: 9),
    this.flashEvery = const Duration(milliseconds: 4200),
    this.flashLength = const Duration(milliseconds: 1400),
    this.restingGlow = .12,
    this.variety = .3,
    this.clearance = 24,
    this.appearAfter = const Duration(milliseconds: 300),
    this.fadeIn = const Duration(milliseconds: 900),
    this.framesPerSecond = 30,
    this.seed = 7,
  });

  /// On charcoal: a pale yellow-green, like a real firefly.
  static const dark = FireflyStyle(color: Color(0xFFF6E27F));

  /// On cream nothing can glow brighter than the background, so these are
  /// embers instead: a soft coral haze around a red-orange centre.
  static const light = FireflyStyle(
    color: Color(0xFFFF8468),
    coreColor: Color(0xFFEB432E),
    glowRadius: 9,
    coreRadius: 1.9,
    restingGlow: .3,
  );

  /// Colour of the glow.
  final Color color;

  /// Colour of the sharp centre. Null draws it lighter than [color], which
  /// suits a dark background.
  final Color? coreColor;

  /// How many fireflies. Cost grows with this, but 30 is still cheap.
  final int count;

  /// Radius of the soft glow, in logical pixels.
  final double glowRadius;

  /// Radius of the bright centre, in logical pixels.
  final double coreRadius;

  /// How far a firefly drifts from its home spot, in logical pixels.
  final double wander;

  /// About how long one slow loop of drifting takes.
  final Duration wanderPeriod;

  /// About how often a firefly flashes.
  final Duration flashEvery;

  /// How long one flash lasts, from dark to bright and back.
  final Duration flashLength;

  /// Brightness between flashes, 0 (invisible) to 1 (full).
  final double restingGlow;

  /// How much fireflies differ from each other in size, speed and rhythm:
  /// 0 makes them all the same, .5 lets each be half as much again or less.
  final double variety;

  /// Gap, in logical pixels, between the logo and the nearest a firefly's
  /// glow ever gets. The logo and wordmark sit inside a circle; fireflies
  /// are spread evenly over the rest of the screen and never drift into it.
  final double clearance;

  /// Nothing is drawn before this, so the hand-off from the system's launch
  /// screen (which has no fireflies) does not change a pixel.
  final Duration appearAfter;

  /// How long the fireflies take to fade in after [appearAfter].
  final Duration fadeIn;

  /// Most repaints per second. Slow, soft motion looks smooth at 30 and
  /// costs half of 60. Above the screen's own rate it makes no difference.
  final int framesPerSecond;

  /// Picks where each firefly lives and its rhythm. Change it for a
  /// different arrangement; the same seed always gives the same picture.
  final int seed;
}

/// Fireflies drifting and flashing over whatever is behind them, kept clear
/// of a [clearOf]-sized box in the middle (the logo). Draws nothing, and runs
/// no animation, when the system asks for reduced motion.
class Fireflies extends StatefulWidget {
  const Fireflies({super.key, required this.style, this.clearOf = Size.zero});
  final FireflyStyle style;

  /// Size of what sits in the centre and must stay uncovered.
  final Size clearOf;

  @override
  State<Fireflies> createState() => _FirefliesState();
}

class _FirefliesState extends State<Fireflies>
    with SingleTickerProviderStateMixin {
  // The ticker pauses by itself when another screen covers this one.
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier(Duration.zero);
  bool _still = false;

  void _tick(Duration elapsed) {
    final fps = widget.style.framesPerSecond;
    final gap = fps <= 0
        ? Duration.zero
        : Duration(microseconds: Duration.microsecondsPerSecond ~/ fps);
    // Only the painter listens to this, so nothing else is rebuilt.
    if (elapsed - _time.value >= gap) _time.value = elapsed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _time.value = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _still
      ? const SizedBox.shrink()
      : IgnorePointer(
          // Repaints stay inside this layer; the logo is not redrawn.
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: FireflyPainter(
                style: widget.style,
                time: _time,
                clearOf: widget.clearOf,
              ),
            ),
          ),
        );
}

/// One firefly's fixed traits, chosen once from the seed. Positions and
/// brightness are worked out from these and the time, so nothing is stored
/// or allocated from frame to frame.
class _Fly {
  factory _Fly(math.Random r, FireflyStyle style) {
    double vary() => 1 + style.variety * (r.nextDouble() * 2 - 1);
    final size = vary();
    final turn = 2 * math.pi / _seconds(style.wanderPeriod);
    return _Fly._(
      size: size,
      glow: MaskFilter.blur(BlurStyle.normal, style.glowRadius * size / 2),
      speedX: turn * vary(),
      speedY: turn * vary() * .8,
      phaseX: r.nextDouble() * 2 * math.pi,
      phaseY: r.nextDouble() * 2 * math.pi,
      flashEvery: _seconds(style.flashEvery) * vary(),
      flashPhase: r.nextDouble(),
    );
  }
  _Fly._({
    required this.size,
    required this.glow,
    required this.speedX,
    required this.speedY,
    required this.phaseX,
    required this.phaseY,
    required this.flashEvery,
    required this.flashPhase,
  });

  /// This firefly's size compared with the style's radii.
  final double size;

  /// The soft edge of its glow.
  final MaskFilter glow;

  /// Drift speeds in radians per second, and where in the drift it starts.
  final double speedX, speedY, phaseX, phaseY;

  /// Seconds between flashes, and where in that rhythm it starts (0 to 1).
  final double flashEvery, flashPhase;
}

double _seconds(Duration d) =>
    d.inMicroseconds / Duration.microsecondsPerSecond;

/// Candidates tried for each home spot; the one furthest from the others
/// wins. More gives a more even spread, fewer a more random one.
const _candidates = 12;

class FireflyPainter extends CustomPainter {
  FireflyPainter({
    required this.style,
    required this.time,
    this.clearOf = Size.zero,
  }) : super(repaint: time);
  final FireflyStyle style;
  final ValueListenable<Duration> time;
  final Size clearOf;

  /// Radius of the circle around the centre that no glow reaches: half the
  /// logo's diagonal plus the style's clearance. Zero when nothing is kept
  /// clear.
  static double clearRadius(Size clearOf, FireflyStyle style) =>
      clearOf.isEmpty ? 0 : _halfDiagonal(clearOf) + style.clearance;

  static double _halfDiagonal(Size s) =>
      math.sqrt(s.width * s.width + s.height * s.height) / 2;

  late final List<_Fly> _flies = () {
    final r = math.Random(style.seed);
    return [for (var i = 0; i < style.count; i++) _Fly(r, style)];
  }();

  // Home spots depend on the screen size, so they are worked out again only
  // when it changes (a rotation), not on every frame.
  Size? _homesSize;
  List<Offset?> _homes = const [];

  /// Spreads the homes evenly over the screen outside the clear circle
  /// ("best candidate" sampling). A home may be null when the screen is too
  /// small to fit it; that firefly is not drawn.
  List<Offset?> _homesFor(Size size) {
    if (size == _homesSize) return _homes;
    final r = math.Random(style.seed + 1);
    // How far a firefly's light can reach from its home: drift plus glow.
    // The glow is a circle of half the glow radius blurred by the same
    // amount, and a blur fades out about three times that far: twice the
    // glow radius in all, for the largest firefly.
    final reach = style.wander + 2 * style.glowRadius * (1 + style.variety);
    final clear = clearRadius(clearOf, style);
    final keepOut = clear == 0 ? 0.0 : clear + reach;
    final centre = size.center(Offset.zero);
    final edge = style.glowRadius;
    final homes = <Offset?>[];
    for (var i = 0; i < style.count; i++) {
      Offset? best;
      var bestGap = -1.0;
      // Bounded: on a small screen most candidates fall in the clear circle.
      var found = 0;
      for (
        var tries = 0;
        found < _candidates && tries < _candidates * 40;
        tries++
      ) {
        final p = Offset(
          edge + r.nextDouble() * math.max(size.width - 2 * edge, 0),
          edge + r.nextDouble() * math.max(size.height - 2 * edge, 0),
        );
        if ((p - centre).distance < keepOut) continue;
        found++;
        var gap = double.infinity;
        for (final h in homes) {
          if (h != null) gap = math.min(gap, (p - h).distance);
        }
        if (gap > bestGap) {
          best = p;
          bestGap = gap;
        }
      }
      homes.add(best);
    }
    _homesSize = size;
    return _homes = homes;
  }

  late final Color _coreColor =
      style.coreColor ?? Color.lerp(style.color, const Color(0xFFFFFFFF), .6)!;

  // Reused for every firefly on every frame.
  final _paint = Paint();

  /// How far the fade-in has got at [t] seconds, from 0 to 1.
  double _fade(double t) {
    final since = t - _seconds(style.appearAfter);
    final length = _seconds(style.fadeIn);
    if (since < 0) return 0;
    return length <= 0 ? 1 : math.min(since / length, 1);
  }

  /// Brightness of one firefly at [t] seconds, from 0 to 1.
  double _brightness(_Fly fly, double t) {
    final share = math.min(_seconds(style.flashLength) / fly.flashEvery, 1);
    final at = (t / fly.flashEvery + fly.flashPhase) % 1;
    if (at >= share) return style.restingGlow;
    // A smooth swell and fade: sin² rises and falls with no sharp corners.
    final s = math.sin(math.pi * at / share);
    return style.restingGlow + (1 - style.restingGlow) * s * s;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = _seconds(time.value);
    final fade = _fade(t);
    if (fade == 0) return;
    final homes = _homesFor(size);
    for (var i = 0; i < _flies.length; i++) {
      final fly = _flies[i];
      final home = homes[i];
      if (home == null) continue;
      final light = fade * _brightness(fly, t);
      if (light < 1 / 255) continue;
      // Two sine waves per direction, at unrelated speeds, so the path never
      // visibly repeats. Each sum stays within ±1, so a firefly stays within
      // `wander` of its home.
      final drift = Offset(
        math.sin(t * fly.speedX + fly.phaseX) * .7 +
            math.sin(t * fly.speedX * 2.3 + fly.phaseY) * .3,
        math.sin(t * fly.speedY + fly.phaseY) * .7 +
            math.sin(t * fly.speedY * 1.7 + fly.phaseX) * .3,
      );
      final at = home + drift * style.wander;
      // The glow: a blurred circle. Both of Flutter's renderers draw a
      // blurred circle in one cheap step, without an offscreen pass.
      _paint
        ..color = style.color.withValues(alpha: style.color.a * light)
        ..maskFilter = fly.glow;
      canvas.drawCircle(at, style.glowRadius * fly.size / 2, _paint);
      // The centre, sharp.
      _paint
        ..color = _coreColor.withValues(alpha: _coreColor.a * light)
        ..maskFilter = null;
      canvas.drawCircle(at, style.coreRadius * fly.size, _paint);
    }
  }

  @override
  bool shouldRepaint(FireflyPainter old) =>
      old.style != style || old.time != time || old.clearOf != clearOf;
}
