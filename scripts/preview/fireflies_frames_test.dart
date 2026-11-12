// Renders the loading screen's fireflies to frames and a page that plays them,
// with no phone, emulator or app launch:
//
//   flutter test scripts/preview/fireflies_frames_test.dart
//
// then open build/previews/fireflies/index.html in a browser. Edit FireflyStyle
// in lib/src/styles/brand/fireflies.dart and run the command again.
//
// Set PREVIEW_SECONDS for a longer or shorter clip (default 8).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _fps = 30;
const _size = Size(390, 844);
const _pixelRatio = 2.0;
final _out = Directory('build/previews/fireflies');
final _seconds =
    int.tryParse(Platform.environment['PREVIEW_SECONDS'] ?? '') ?? 8;

void main() {
  setUpAll(() {
    if (_out.existsSync()) _out.deleteSync(recursive: true);
    _out.createSync(recursive: true);
  });
  tearDownAll(() => _writePage(_out, _seconds * _fps));

  for (final brightness in Brightness.values) {
    testWidgets('fireflies ${brightness.name}', (tester) async {
      tester.view.physicalSize = _size * _pixelRatio;
      tester.view.devicePixelRatio = _pixelRatio;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: fireplaceTheme(brightness),
          home: RepaintBoundary(key: boundary, child: const FireplaceSplash()),
        ),
      );
      final frames = _seconds * _fps;
      for (var i = 0; i < frames; i++) {
        await tester.pump(
          const Duration(microseconds: Duration.microsecondsPerSecond ~/ _fps),
        );
        final png = await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: _pixelRatio);
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
          }
        });
        File('${_out.path}/${brightness.name}-${'$i'.padLeft(4, '0')}.png')
            .writeAsBytesSync(png!);
      }
    });
  }
}

// The page decodes only a short window of frames ahead of the playhead and
// draws them on a canvas. Decoding every frame up front needs gigabytes, and
// a browser that evicts and re-decodes them shows frames late or skips them,
// which looks like fireflies jumping. Playback never skips a frame: when the
// next one is not decoded yet it waits, so motion is exactly what the app
// draws, at worst briefly slower.
void _writePage(Directory out, int frames) {
  final w = _size.width.toInt(), h = _size.height.toInt();
  final pw = (_size.width * _pixelRatio).toInt();
  final ph = (_size.height * _pixelRatio).toInt();
  File('${out.path}/index.html').writeAsStringSync('''
<!DOCTYPE html>
<html lang="en">
<meta charset="utf-8">
<title>Fireflies preview</title>
<style>
  body { margin: 0; background: #222; color: #eee; font: 14px system-ui, sans-serif; }
  .screens { display: flex; gap: 24px; justify-content: center; padding: 24px; flex-wrap: wrap; }
  canvas { width: ${w}px; height: ${h}px; border-radius: 24px; display: block; background: #111; }
  .bar { display: flex; gap: 16px; align-items: center; justify-content: center; padding: 0 24px 24px; }
  input[type=range] { width: 420px; }
  #status { min-width: 9em; color: #aaa; }
</style>
<div class="screens">
  <canvas id="dark" width="$pw" height="$ph" aria-label="Dark loading screen"></canvas>
  <canvas id="light" width="$pw" height="$ph" aria-label="Light loading screen"></canvas>
</div>
<div class="bar">
  <button id="play">Pause</button>
  <input id="scrub" type="range" min="0" max="${frames - 1}" value="0">
  <span id="time"></span>
  <span id="status"></span>
  <label><input id="loop" type="checkbox" checked> Loop</label>
</div>
<script>
  const frames = $frames, fps = $_fps, ahead = 45;
  const name = (theme, i) => theme + '-' + String(i).padStart(4, '0') + '.png';
  const screens = { dark: document.getElementById('dark').getContext('2d'),
                    light: document.getElementById('light').getContext('2d') };
  const scrub = document.getElementById('scrub'), time = document.getElementById('time');
  const play = document.getElementById('play'), loop = document.getElementById('loop');
  const status = document.getElementById('status');
  const cache = new Map();
  function load(i) {
    let entry = cache.get(i);
    if (entry) return entry;
    entry = { ready: false, images: {} };
    const decoding = [];
    for (const theme in screens) {
      const image = new Image();
      image.src = name(theme, i);
      entry.images[theme] = image;
      decoding.push(image.decode());
    }
    Promise.all(decoding).then(() => { entry.ready = true; }, () => {});
    cache.set(i, entry);
    return entry;
  }
  const next = (i) => i + 1 < frames ? i + 1 : (loop.checked ? 0 : -1);
  // Keep the frames from the playhead to `ahead` frames on; drop the rest.
  function buffer(from) {
    const keep = new Set();
    for (let i = from, n = 0; i >= 0 && n <= ahead; i = next(i), n++) {
      keep.add(i);
      load(i);
      if (i === frames - 1 && !loop.checked) break;
    }
    for (const k of cache.keys()) if (!keep.has(k)) cache.delete(k);
  }
  let frame = 0, playing = true, due = 0;
  function draw(i) {
    const entry = cache.get(i);
    if (!entry || !entry.ready) return false;
    for (const theme in screens) screens[theme].drawImage(entry.images[theme], 0, 0);
    scrub.value = i;
    time.textContent = ((i + 1) / fps).toFixed(2) + ' s';
    return true;
  }
  function seek(i) { frame = i; buffer(i); due = 0; }
  function tick(now) {
    requestAnimationFrame(tick);
    buffer(frame);
    if (!draw(frame)) { status.textContent = 'decoding…'; return; }
    if (!playing) { status.textContent = ''; return; }
    if (due === 0) due = now + 1000 / fps;
    if (now < due) return;
    const n = next(frame);
    if (n < 0) return;
    const entry = cache.get(n);
    if (!entry || !entry.ready) { status.textContent = 'buffering…'; due = now; return; }
    status.textContent = '';
    frame = n;
    // Falling far behind restarts the clock instead of racing to catch up.
    due = now - due > 100 ? now + 1000 / fps : due + 1000 / fps;
  }
  play.onclick = () => { playing = !playing; play.textContent = playing ? 'Pause' : 'Play'; due = 0; };
  scrub.oninput = () => seek(Number(scrub.value));
  seek(0);
  requestAnimationFrame(tick);
</script>
</html>
''');
}
