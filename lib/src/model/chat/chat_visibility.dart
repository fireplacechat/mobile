import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';

class ChatVisibility extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    return null;
  }

  void show(String? id) {
    if (ref.mounted) state = id;
  }

  void clearIf(String id) {
    if (ref.mounted && state == id) state = null;
  }
}

final visibleChatProvider = NotifierProvider<ChatVisibility, String?>(
  ChatVisibility.new,
);
