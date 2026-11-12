import 'dart:async';

import 'package:fireplace/fireplace_services.dart';

/// Runs before every test file. Pacing against the server's rate limit would
/// make tests that send many messages crawl, and there are no rules to obey.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ChatService.pacing = false;
  await testMain();
}
