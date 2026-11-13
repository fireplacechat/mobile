import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final externalBrowserProvider = Provider<ExternalBrowser>(
  (_) => const ChannelExternalBrowser(),
);

abstract interface class ExternalBrowser {
  /// Requests the phone's browser; false means it could not be opened.
  Future<bool> open(Uri url);
}

class ChannelExternalBrowser implements ExternalBrowser {
  const ChannelExternalBrowser();
  static const _channel = MethodChannel('fireplace/browser');

  @override
  Future<bool> open(Uri url) async {
    if (url.scheme != 'https' || url.host.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('open', url.toString()) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
