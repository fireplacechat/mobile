// The same matrix as the 320x640 and 768x1024 files, at one more size.
@Tags(['nightly'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/accessibility_matrix.dart';

void main() => defineAccessibilityMatrix([accessibilitySizes[2]]);
