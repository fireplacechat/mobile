import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colour painted at [at] inside the RepaintBoundary under [boundary],
/// in its logical pixels. Use a view with a device pixel ratio of 1.
Future<Color> paintedPixel(
  WidgetTester t,
  GlobalKey boundary,
  Offset at,
) async {
  final box =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await t.runAsync(() async {
    final image = await box.toImage();
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  });
  final index = at.dy.floor() * box.size.width.round() + at.dx.floor();
  final rgba = bytes!.getUint32(index * 4);
  return Color.fromARGB(
    rgba & 0xff,
    rgba >> 24,
    (rgba >> 16) & 0xff,
    (rgba >> 8) & 0xff,
  );
}
