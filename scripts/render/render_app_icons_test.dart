// Export the approved flame geometry with a raised enamel finish for iOS.
// flutter test scripts/render/render_app_icons_test.dart
// Exports stay in build/icon-exports until copied into the app's asset catalog.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// App Store icons must have no alpha channel, even when every pixel is opaque.
Uint8List rgbPng(Uint8List rgba, int edge) {
  final rows = Uint8List(edge * (1 + edge * 3));
  var target = 0;
  for (var y = 0; y < edge; y++) {
    rows[target++] = 0; // Unfiltered RGB scanline.
    for (var x = 0; x < edge; x++) {
      final source = (y * edge + x) * 4;
      rows[target++] = rgba[source];
      rows[target++] = rgba[source + 1];
      rows[target++] = rgba[source + 2];
    }
  }
  final output = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> payload) {
    final body = [...ascii.encode(type), ...payload];
    var crc = 0xffffffff;
    for (final byte in body) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    output
      ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
      ..add(body)
      ..add((ByteData(4)..setUint32(0, crc ^ 0xffffffff)).buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, edge)
    ..setUint32(4, edge)
    ..setUint8(8, 8)
    ..setUint8(9, 2); // Truecolour RGB, without alpha or provenance metadata.
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(rows));
  chunk('IEND', const []);
  return output.toBytes();
}

void paintIcon(Canvas canvas, int pixels) {
  canvas.scale(pixels / 1024);
  const bounds = Rect.fromLTWH(0, 0, 1024, 1024);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFC15A04), fireplaceOrange, Color(0xFFB85401)],
        stops: [0, .5, 1],
      ).createShader(bounds),
  );
  // A broad, low-opacity reflection keeps the burnt orange recognisable.
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.65, -.9),
        radius: 1.35,
        colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
      ).createShader(bounds),
  );

  // Keep the source opaque and full bleed. iOS applies the final corner mask.
  final rim = Path();
  for (var i = 0; i <= 256; i++) {
    final angle = i * math.pi * 2 / 256;
    final c = math.cos(angle), s = math.sin(angle);
    final x = 512 + 504 * c.sign * math.pow(c.abs(), .4);
    final y = 512 + 504 * s.sign * math.pow(s.abs(), .4);
    if (i == 0) {
      rim.moveTo(x, y);
    } else {
      rim.lineTo(x, y);
    }
  }
  rim.close();
  // Light extends outward from this inner bevel, through and beyond the OS
  // mask. An inset stroke leaves an orange strip outside its brightest edge.
  final outerEdge = Path.combine(
    PathOperation.difference,
    Path()..addRect(bounds.inflate(64)),
    rim,
  );
  const rimLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xB8FFFFFF),
      Color(0x24FFFFFF),
      Color(0x00FFFFFF),
      Color(0x18FFFFFF),
      Color(0x98FFFFFF),
    ],
    stops: [0, .27, .5, .73, 1],
  );
  canvas.drawPath(
    outerEdge,
    Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..shader = rimLight.createShader(bounds),
  );
  canvas.drawPath(
    outerEdge,
    Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
      ..shader = rimLight.createShader(bounds),
  );

  // Match the current launcher mark's 78% master scale and centred placement.
  final mark = FlamePainter.master()
      .transform(Matrix4.diagonal3Values(.78, .78, 1).storage)
      .shift(const Offset(112.64, 112.64));
  canvas.drawPath(
    mark.shift(const Offset(1, 12)),
    Paint()
      ..color = const Color(0x493F1A00)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
  );
  canvas.drawPath(
    mark.shift(const Offset(0, 5)),
    Paint()..color = const Color(0xFFDDD0BE),
  );
  canvas.drawPath(
    mark,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFEFB), Color(0xFFFAF7F0), Color(0xFFF0EADF)],
        stops: [0, .55, 1],
      ).createShader(mark.getBounds()),
  );
  // Directional inner edges give the original silhouette a rounded face.
  canvas.save();
  canvas.clipPath(mark);
  canvas.drawPath(
    Path.combine(
      PathOperation.difference,
      mark,
      mark.shift(const Offset(-14, -16)),
    ),
    Paint()
      ..color = const Color(0x605D4933)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
  canvas.drawPath(
    Path.combine(
      PathOperation.difference,
      mark,
      mark.shift(const Offset(10, 12)),
    ),
    Paint()
      ..color = const Color(0xF0FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  canvas.restore();
}

void main() {
  testWidgets('corner highlights continue out to the masked edge', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final pixels in [1024, 180, 120, 60]) {
        final recorder = ui.PictureRecorder();
        paintIcon(Canvas(recorder), pixels);
        final picture = recorder.endRecording();
        final image = await picture.toImage(pixels, pixels);
        try {
          final rgba = (await image.toByteData())!.buffer.asUint8List();
          for (final bottomRight in [false, true]) {
            var previous = 0;
            // Follow each lit corner outward. An inset stroke gets bright and
            // then orange again; a bevel must stay lit through the outer crop.
            for (final fraction in [.10, .09, .08, .07, .06, .05, .04]) {
              final near = (pixels * fraction).floor();
              final coordinate = bottomRight ? pixels - 1 - near : near;
              final index = (coordinate * pixels + coordinate) * 4;
              final light = rgba[index] + rgba[index + 1] + rgba[index + 2];
              expect(
                light,
                greaterThanOrEqualTo(previous - 3),
                reason: 'No orange strip outside the highlight at $pixels px',
              );
              previous = light;
            }
          }
        } finally {
          image.dispose();
          picture.dispose();
        }
      }
    });
  });

  testWidgets('export opaque iOS icons from the approved vector mark', (
    tester,
  ) async {
    final catalog = jsonDecode(
      File('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final exports = <String, int>{'fireplace_ios.png': 1024};
    for (final item
        in (catalog['images'] as List).cast<Map<String, dynamic>>()) {
      final logical = double.parse((item['size'] as String).split('x').first);
      final scale = double.parse((item['scale'] as String).replaceAll('x', ''));
      exports[item['filename'] as String] = (logical * scale).round();
    }
    await tester.runAsync(() async {
      final output = Directory('build/icon-exports')
        ..createSync(recursive: true);
      for (final entry in exports.entries) {
        final recorder = ui.PictureRecorder();
        paintIcon(Canvas(recorder), entry.value);
        final picture = recorder.endRecording();
        final image = await picture.toImage(entry.value, entry.value);
        try {
          final rgba = (await image.toByteData())!.buffer.asUint8List();
          expect(
            [for (var i = 3; i < rgba.length; i += 4) rgba[i]]
                .every((a) => a == 255),
            isTrue,
            reason: 'App Store icons must be opaque',
          );
          final png = rgbPng(rgba, entry.value);
          final codec = await ui.instantiateImageCodec(png);
          final decoded = (await codec.getNextFrame()).image;
          try {
            expect((await decoded.toByteData())!.buffer.asUint8List(), rgba);
          } finally {
            decoded.dispose();
            codec.dispose();
          }
          File('${output.path}/${entry.key}').writeAsBytesSync(png);
        } finally {
          image.dispose();
          picture.dispose();
        }
      }
    });
  });
}
