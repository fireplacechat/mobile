// Export the approved flame geometry with a subtle surface finish for iOS.
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
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFC45D08), fireplaceOrange, Color(0xFFB45100)],
        stops: [0, .5, 1],
      ).createShader(bounds),
  );

  // Keep the source opaque and full bleed. iOS applies the final corner mask.
  final rim = Path();
  for (var i = 0; i <= 256; i++) {
    final angle = i * math.pi * 2 / 256;
    final c = math.cos(angle), s = math.sin(angle);
    final x = 512 + 510 * c.sign * math.pow(c.abs(), .4);
    final y = 512 + 510 * s.sign * math.pow(s.abs(), .4);
    if (i == 0) {
      rim.moveTo(x, y);
    } else {
      rim.lineTo(x, y);
    }
  }
  rim.close();
  canvas.drawPath(
    rim,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x80FFFFFF), Color(0x08FFFFFF), Color(0x183F1A00)],
        stops: [0, .55, 1],
      ).createShader(bounds),
  );

  // Match the current launcher mark's 78% master scale and centred placement.
  final mark = FlamePainter.master()
      .transform(Matrix4.diagonal3Values(.78, .78, 1).storage)
      .shift(const Offset(112.64, 112.64));
  canvas.drawPath(
    mark.shift(const Offset(0, 3)),
    Paint()
      ..color = const Color(0x303F1A00)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
  );
  canvas.drawPath(
    mark,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFDFAF5), Color(0xFFFAF7F0), Color(0xFFF4EFE6)],
      ).createShader(bounds),
  );
  // A clipped edge catch adds depth without changing the flame silhouettes.
  canvas.save();
  canvas.clipPath(mark);
  canvas.drawPath(
    mark.shift(const Offset(0, 1.5)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xA0FFFFFF),
  );
  canvas.restore();
}

void main() {
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
