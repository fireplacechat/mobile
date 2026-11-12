// The loading screen on its own, kept on screen, for working on the
// fireflies. Nothing here signs in or touches Firebase.
//
//   flutter run -t scripts/preview/fireflies_preview.dart
//
// Edit FireflyStyle in lib/src/styles/brand/fireflies.dart and press `r` to
// hot reload. Tap the screen to switch between the light and dark versions;
// press `R` (hot restart) to watch the fade-in again.
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';

void main() => runApp(const FirefliesPreview());

class FirefliesPreview extends StatefulWidget {
  const FirefliesPreview({super.key});

  @override
  State<FirefliesPreview> createState() => _FirefliesPreviewState();
}

class _FirefliesPreviewState extends State<FirefliesPreview> {
  var _brightness = Brightness.dark;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: fireplaceTheme(_brightness),
    home: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(
        () => _brightness = _brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: const FireplaceSplash(),
    ),
  );
}
