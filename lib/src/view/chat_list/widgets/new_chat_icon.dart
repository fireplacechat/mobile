import 'package:flutter/material.dart';

/// The approved speech-bubble-plus silhouette, traced from the owner's
/// reference into a 24-point view box. Keep this size independent of text scale.
class NewChatIcon extends StatelessWidget {
  const NewChatIcon({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size.square(24),
      painter: _NewChatPainter(
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onPrimary,
      ),
    ),
  );
}

class _NewChatPainter extends CustomPainter {
  const _NewChatPainter(this.color);
  final Color color;

  static final _bubble = Path()
    ..moveTo(11.620, 1.542)
    ..cubicTo(7.407, 1.692, 3.302, 4.424, 1.882, 8.407)
    ..cubicTo(1.249, 10.183, 1.151, 12.209, 1.674, 14.032)
    ..cubicTo(1.942, 14.971, 2.376, 15.855, 2.351, 16.792)
    ..cubicTo(2.325, 17.757, 1.811, 18.777, 1.358, 19.593)
    ..cubicTo(1.232, 19.820, 1.111, 20.032, 1.181, 20.219)
    ..cubicTo(1.251, 20.406, 1.513, 20.568, 1.770, 20.707)
    ..cubicTo(2.248, 20.965, 2.712, 21.142, 3.205, 21.271)
    ..cubicTo(4.094, 21.502, 5.076, 21.574, 5.990, 21.383)
    ..cubicTo(6.951, 21.182, 7.835, 20.690, 8.762, 21.056)
    ..cubicTo(9.240, 21.245, 9.729, 21.662, 10.172, 21.707)
    ..cubicTo(10.577, 21.749, 10.944, 21.481, 11.042, 21.070)
    ..cubicTo(11.143, 20.649, 10.961, 20.077, 10.630, 19.773)
    ..cubicTo(10.286, 19.456, 9.781, 19.428, 9.323, 19.254)
    ..cubicTo(8.849, 19.074, 8.425, 18.736, 7.968, 18.733)
    ..cubicTo(7.512, 18.729, 7.024, 19.060, 6.549, 19.268)
    ..cubicTo(6.097, 19.467, 5.657, 19.556, 5.144, 19.573)
    ..cubicTo(4.632, 19.590, 4.049, 19.536, 3.888, 19.250)
    ..cubicTo(3.722, 18.954, 4.008, 18.410, 4.168, 17.885)
    ..cubicTo(4.313, 17.412, 4.355, 16.954, 4.323, 16.512)
    ..cubicTo(4.254, 15.556, 3.838, 14.669, 3.582, 13.726)
    ..cubicTo(3.341, 12.836, 3.242, 11.895, 3.320, 10.975)
    ..cubicTo(3.497, 8.866, 4.601, 6.869, 6.209, 5.529)
    ..cubicTo(9.270, 2.979, 14.157, 2.805, 17.388, 5.198)
    ..cubicTo(18.308, 5.879, 19.093, 6.768, 19.634, 7.757)
    ..cubicTo(20.112, 8.633, 20.399, 9.587, 20.700, 10.451)
    ..cubicTo(20.773, 10.661, 20.847, 10.865, 21.048, 10.976)
    ..cubicTo(21.230, 11.077, 21.518, 11.100, 21.792, 11.082)
    ..cubicTo(22.065, 11.064, 22.324, 11.004, 22.448, 10.879)
    ..cubicTo(22.577, 10.748, 22.561, 10.548, 22.537, 10.341)
    ..cubicTo(22.433, 9.466, 22.171, 8.487, 21.768, 7.588)
    ..cubicTo(20.053, 3.769, 15.784, 1.395, 11.620, 1.542)
    ..close();
  static final _plus = Path()
    ..addRect(const Rect.fromLTRB(17, 14, 19, 22))
    ..addRect(const Rect.fromLTRB(14, 17, 22, 19));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = color;
    canvas.drawPath(_bubble, paint);
    canvas.drawPath(_plus, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NewChatPainter oldDelegate) => color != oldDelegate.color;
}
