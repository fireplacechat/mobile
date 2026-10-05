// REVIEW R02b (iOS, needs macOS to verify the build): the iOS launch screen has one cream background and no
// dark appearance, so dark-mode phones flash cream before the charcoal splash. This only checks the files.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS launch image has a dark appearance variant', () {
    final f = File(
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json',
    );
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final images = (json['images'] as List).cast<Map<String, dynamic>>();
    final dark = images.where(
      (i) =>
          (i['appearances'] as List?)?.any((a) => a['value'] == 'dark') ??
          false,
    );
    expect(dark, isNotEmpty, reason: 'add 1x/2x/3x dark LaunchImage entries');
  });

  test('iOS launch storyboard background comes from a named colour that has a dark variant', () {
    final sb = File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
        .readAsStringSync();
    expect(sb, contains('name="LaunchBackground"'));
    final cs = File(
      'ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json',
    );
    expect(cs.existsSync(), isTrue);
    expect(cs.readAsStringSync(), contains('"dark"'));
  });
}
