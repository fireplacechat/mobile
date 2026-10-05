import 'dart:async';

import 'package:fireplace/fireplace_services.dart';

/// Runs before every test file. The production send gap (pacing against the
/// server's rate limit) would make tests that send many messages crawl.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ChatService.sendGap = Duration.zero;
  await testMain();
}
