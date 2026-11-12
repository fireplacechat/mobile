import 'dart:async';

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/qr_scan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../support/ui_fixture.dart';

const _cameraChannel = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/method',
);

/// Stands in for the camera plugin. [start] never touches the device.
class _FakeCamera extends MobileScannerPlatform {
  _FakeCamera({this.failStart = false});

  final bool failStart;
  var starts = 0;
  final _codes = StreamController<BarcodeCapture?>.broadcast();
  final _torch = StreamController<TorchState>.broadcast();
  final _zoom = StreamController<double>.broadcast();

  void emit(String? raw) {
    _codes.add(BarcodeCapture(barcodes: [Barcode(rawValue: raw)]));
  }

  @override
  Stream<BarcodeCapture?> get barcodesStream => _codes.stream;

  @override
  Stream<TorchState> get torchStateStream => _torch.stream;

  @override
  Stream<double> get zoomScaleStateStream => _zoom.stream;

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    starts += 1;
    if (failStart) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
    );
  }

  @override
  Widget buildCameraView() => const SizedBox(key: Key('fake-camera'));

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> toggleTorch() async {}

  @override
  Future<void> resetZoomScale() async {}

  @override
  Future<void> setZoomScale(double zoomScale) async {}

  @override
  Future<void> setFocusPoint(Offset position) async {}

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) async => null;

  @override
  Future<Set<CameraLensType>> getSupportedLenses({
    CameraFacing? facing,
  }) async => {CameraLensType.normal};

  @override
  Future<CameraLensType?> getBestCloseRangeScanningLens({
    CameraFacing facing = CameraFacing.back,
  }) async => CameraLensType.normal;

  Future<void> close() async {
    await _codes.close();
    await _torch.close();
    await _zoom.close();
  }
}

/// Gives [child] a real height. A full-screen route would ignore a bare box.
Widget bounded(double height, Widget child) => Align(
  alignment: Alignment.topCenter,
  child: SizedBox(height: height, width: 320, child: child),
);

Future<void> pump(WidgetTester t, UiFixture f, Widget home) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
    ),
  );
}

/// Opens the scanner on a route that can pop, and returns what it popped with.
Future<String?> openScanner(
  WidgetTester t,
  UiFixture f, {
  String title = 'Scan code',
}) async {
  String? scanned;
  await pump(
    t,
    f,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            scanned = await Navigator.of(context).push<String>(
              MaterialPageRoute<String>(
                builder: (_) => QrScanPage(title: title),
              ),
            );
          },
          child: const Text('Open scanner'),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open scanner'));
  // Let the camera future finish before settling, so the spinner is gone.
  await t.pump();
  await t.pump();
  await t.pumpAndSettle();
  return scanned;
}

void main() {
  late MobileScannerPlatform realCamera;

  setUp(() {
    realCamera = MobileScannerPlatform.instance;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cameraChannel, (call) {
          throw StateError('camera plugin method ${call.method}');
        });
  });

  tearDown(() {
    MobileScannerPlatform.instance = realCamera;
    MobileScannerController.resetPlatformSessionOwner();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cameraChannel, null);
  });

  testWidgets('a denied camera shows plain words and go back leaves', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    final camera = _FakeCamera(failStart: true);
    MobileScannerPlatform.instance = camera;
    addTearDown(camera.close);
    String? scanned;
    var left = false;
    await pump(
      t,
      f,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              scanned = await Navigator.of(context).push<String>(
                MaterialPageRoute<String>(builder: (_) => const QrScanPage()),
              );
              left = true;
            },
            child: const Text('Open scanner'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open scanner'));
    await t.pump();
    await t.pump();
    await t.pumpAndSettle();
    expect(camera.starts, 1);
    expect(find.text('Scan code'), findsOneWidget);
    expect(find.text('Camera is unavailable'), findsOneWidget);
    expect(
      find.text(
        'Allow camera access in your device settings, then try again. You can also go back.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Go back'));
    await t.pumpAndSettle();
    expect(left, isTrue);
    expect(scanned, isNull);
    expect(find.text('Camera is unavailable'), findsNothing);
  });

  testWidgets('a scanned code is returned and a second code is ignored', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    final camera = _FakeCamera();
    MobileScannerPlatform.instance = camera;
    addTearDown(camera.close);
    String? scanned;
    await pump(
      t,
      f,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              scanned = await Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) =>
                      const QrScanPage(title: 'Scan the new device'),
                ),
              );
            },
            child: const Text('Open scanner'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open scanner'));
    await t.pump();
    await t.pump();
    await t.pumpAndSettle();
    expect(find.text('Scan the new device'), findsOneWidget);
    expect(find.byKey(const Key('fake-camera')), findsOneWidget);
    expect(camera.starts, 1);
    camera.emit('fireplace:example-device');
    camera.emit('fireplace:ignored');
    await t.pumpAndSettle();
    expect(scanned, 'fireplace:example-device');
    expect(find.text('Scan the new device'), findsNothing);
  });

  testWidgets('a code with no value leaves the scanner open', (t) async {
    final f = UiFixture();
    await f.seed();
    final camera = _FakeCamera();
    MobileScannerPlatform.instance = camera;
    addTearDown(camera.close);
    await openScanner(t, f);
    expect(find.text('Scan code'), findsOneWidget);
    camera.emit(null);
    await t.pump();
    expect(find.text('Scan code'), findsOneWidget);
    expect(find.text('Open scanner'), findsNothing);
  });

  testWidgets('a tall body is not scrolled and a short one is', (t) async {
    final f = UiFixture();
    await f.seed();
    var taps = 0;
    await pump(
      t,
      f,
      bounded(400, const UiBodyViewport(child: Text('The conversation'))),
    );
    expect(find.text('The conversation'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);

    await pump(
      t,
      f,
      bounded(
        200,
        UiBodyViewport(
          child: Column(
            children: [
              const Text('The conversation'),
              TextButton(onPressed: () => taps++, child: const Text('Jump')),
              const TextButton(onPressed: null, child: Text('Wait')),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final slot = t.widget<SizedBox>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(slot.height, 480);
    await t.tap(find.text('Jump'));
    expect(taps, 1);
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, 'Wait')).onPressed,
      isNull,
    );
  });

  testWidgets('a short body anchors to the bottom when asked', (t) async {
    final f = UiFixture();
    await f.seed();
    await pump(
      t,
      f,
      bounded(
        200,
        const UiBodyViewport(anchorBottom: true, child: Text('The composer')),
      ),
    );
    expect(
      t
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .reverse,
      isTrue,
    );
    expect(find.text('The composer'), findsOneWidget);
  });

  testWidgets('large text makes the short body taller', (t) async {
    final f = UiFixture();
    await f.seed();
    await t.pumpWidget(
      ProviderScope(
        overrides: f.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: bounded(
            200,
            const UiBodyViewport(child: Text('Still reachable')),
          ),
        ),
      ),
    );
    final slot = t.widget<SizedBox>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(slot.height, 512);
    expect(find.text('Still reachable'), findsOneWidget);
  });

  testWidgets('a page scroll shows its rows, a tap and a disabled button', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var taps = 0;
    await pump(
      t,
      f,
      UiPageScroll(
        controller: controller,
        children: [
          const Text('Could not save. Try again.'),
          TextButton(onPressed: () => taps++, child: const Text('Save')),
          const TextButton(onPressed: null, child: Text('Wait')),
          const SizedBox(height: 2000),
          const Text('The end'),
        ],
      ),
    );
    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(t.getSize(find.byType(ListView)).width, 600);
    await t.tap(find.text('Save'));
    expect(taps, 1);
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, 'Wait')).onPressed,
      isNull,
    );
    expect(controller.hasClients, isTrue);
    final end = controller.position.maxScrollExtent;
    expect(end, greaterThan(0));
    controller.jumpTo(end);
    expect(controller.offset, end);
    await t.pump();
    expect(find.text('The end'), findsOneWidget);
  });
}
