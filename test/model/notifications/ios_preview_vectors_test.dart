import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../scripts/export_notification_preview_vectors.dart';

void main() {
  test('Swift preview vectors match the unchanged Dart formatter', () {
    final fixture = jsonDecode(
      File('ios/PreviewTests/fixtures/preview-text.json').readAsStringSync(),
    );
    expect(fixture, previewVectors());
  });
}
