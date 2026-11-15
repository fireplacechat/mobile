// The file that tells the iPhone notification extension the app is on screen
// (decision 0056): there while the app is on screen, kept fresh, gone when it
// leaves.
import 'dart:io';

import 'package:fireplace/src/app/ios_foreground_marker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fp_foreground'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('on screen it exists; in the background it is gone', () async {
    final marker = IosForegroundMarker(dir.path);
    marker.start(AppLifecycleState.resumed);
    expect(marker.file.existsSync(), isTrue);
    expect(marker.file.lengthSync(), 0);
    expect(marker.file.path, endsWith(IosForegroundMarker.fileName));
    for (final away in [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ]) {
      marker.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(marker.file.existsSync(), isTrue, reason: 'before $away');
      marker.didChangeAppLifecycleState(away);
      expect(marker.file.existsSync(), isFalse, reason: '$away');
    }
    marker.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await marker.stop();
    expect(marker.file.existsSync(), isFalse);
  });

  test('started in the background, it writes nothing', () async {
    final marker = IosForegroundMarker(dir.path);
    marker.start(AppLifecycleState.paused);
    expect(marker.file.existsSync(), isFalse);
    marker.start(AppLifecycleState.resumed); // a second start changes nothing
    expect(marker.file.existsSync(), isFalse);
    await marker.stop();
  });

  testWidgets('it is touched again on every tick while on screen, and not '
      'after', (t) async {
    final marker = IosForegroundMarker(
      dir.path,
      every: const Duration(seconds: 10),
    );
    marker.start(AppLifecycleState.resumed);
    // Make it look old; the next tick must bring it back to now.
    final old = DateTime.now().subtract(const Duration(minutes: 5));
    marker.file.setLastModifiedSync(old);
    await t.pump(const Duration(seconds: 10));
    expect(
      marker.file.lastModifiedSync().isAfter(
        old.add(const Duration(minutes: 4)),
      ),
      isTrue,
    );
    marker.didChangeAppLifecycleState(AppLifecycleState.paused);
    await t.pump(const Duration(minutes: 1));
    expect(marker.file.existsSync(), isFalse);
    await marker.stop();
  });

  test('a folder that cannot be written is not an error', () async {
    final blocked = File('${dir.path}/not-a-folder')..writeAsStringSync('x');
    final marker = IosForegroundMarker(blocked.path);
    marker.start(AppLifecycleState.resumed);
    marker.didChangeAppLifecycleState(AppLifecycleState.paused);
    await marker.stop();
  });
}
