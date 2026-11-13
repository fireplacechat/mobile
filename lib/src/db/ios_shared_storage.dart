import 'package:flutter/services.dart';

/// Native preparation migrates existing keychain items before returning the
/// resolved signing-prefix access group. No secret crosses this channel.
class IosSharedStorage {
  const IosSharedStorage({
    required this.keychainGroup,
    required this.directory,
  });
  final String keychainGroup;
  final String directory;
  static const _channel = MethodChannel('fireplace/preview_storage');

  static Future<void> protectHistory(String uid) =>
      _channel.invokeMethod<void>('protectHistory', {'uid': uid});

  static Future<IosSharedStorage> prepare() async {
    final result = await _channel.invokeMapMethod<String, String>('prepare');
    final group = result?['keychainGroup'], directory = result?['directory'];
    if (group == null ||
        group.isEmpty ||
        group.contains(r'$(') ||
        directory == null ||
        !directory.startsWith('/')) {
      throw StateError('Could not open secure storage.');
    }
    return IosSharedStorage(keychainGroup: group, directory: directory);
  }
}
