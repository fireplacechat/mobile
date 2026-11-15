import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// Tells the iPhone notification extension that the app is on screen
/// (decision 0056), so it does no work for a push the app is about to receive
/// itself.
///
/// While the app is on screen the system shows no banner (the in-app notice
/// does that), so whatever the extension fetched and decrypted was thrown
/// away. The extension cannot ask iOS whether the app is running, so the app
/// says so: it touches a file in the container the two share about every ten
/// seconds while it is on screen, and removes it when it leaves. The extension
/// treats a file touched in the last half minute as "on screen". A stale file
/// (the app was killed while open) therefore stops counting within half a
/// minute.
///
/// The file is empty. It says nothing about any account or chat.
class IosForegroundMarker with WidgetsBindingObserver {
  IosForegroundMarker(
    String sharedDirectory, {
    this.every = const Duration(seconds: 10),
  }) : file = File('$sharedDirectory/$fileName');

  /// Read by `PreviewForeground` in the extension; keep the two the same.
  static const fileName = 'foreground';

  final File file;
  final Duration every;
  Timer? _timer;
  bool _started = false;

  /// Starts following the app's lifecycle. [state] is the state it is in now.
  void start(AppLifecycleState? state) {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _apply(state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _apply(state);

  void _apply(AppLifecycleState? state) {
    if (state == AppLifecycleState.resumed) {
      _touch();
      _timer ??= Timer.periodic(every, (_) => _touch());
    } else {
      _timer?.cancel();
      _timer = null;
      _remove();
    }
  }

  void _touch() {
    try {
      if (file.existsSync()) {
        file.setLastModifiedSync(DateTime.now());
      } else {
        file.createSync(recursive: true);
      }
    } on FileSystemException {
      // The extension then does its usual work: slower, never wrong.
    }
  }

  void _remove() {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // It goes stale by itself in half a minute.
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _remove();
  }
}
