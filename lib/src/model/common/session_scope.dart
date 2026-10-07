import 'dart:async';

class SessionScope {
  SessionScope({required this.isMounted});

  final bool Function() isMounted;
  bool _stopped = false;
  bool _initialized = false;
  bool _successful = false;
  Future<void>? _closing;
  final _cleaners = <Future<void> Function()>[];

  bool get stopped => _stopped;
  void add(Future<void> Function() cleaner) => _cleaners.add(cleaner);

  Future<void> cleanup() => _closing ??= () async {
    _stopped = true;
    Object? firstError;
    StackTrace? firstStack;
    for (final close in _cleaners.reversed) {
      try {
        await close();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }();
  void checkActive() {
    if (_stopped || !isMounted()) {
      throw StateError('Session initialization cancelled.');
    }
  }

  void disposed() {
    _stopped = true;
    // An awaited constructor/start may still own resources; its finally block
    // closes them when it returns rather than racing that initialization.
    if (_initialized) unawaited(cleanup().catchError((Object _) {}));
  }

  void succeeded() => _successful = true;

  Future<void> finish() async {
    _initialized = true;
    if (!_successful || _stopped) await cleanup();
  }
}
