import 'package:fireplace/src/model/notifications/preview_notifier.dart';

/// Records notifications instead of posting them; keeps what is showing.
class FakePoster implements NotificationPoster {
  final shown = <String, ({String title, String body, String channel})>{};
  final ids = <String, String>{};
  final log = <String>[];

  @override
  Future<void> show({
    required String tag,
    required String title,
    required String body,
    required String messageId,
    required String channel,
    bool silent = false,
  }) async {
    shown[tag] = (title: title, body: body, channel: channel);
    ids[tag] = messageId;
    log.add('show $tag $body${silent ? ' (silent)' : ''}');
  }

  @override
  Future<void> remove(String tag) async {
    shown.remove(tag);
    ids.remove(tag);
    log.add('remove $tag');
  }

  @override
  Future<Map<String, String>> showing() async => Map.of(ids);
}
