import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sendGap is shared between the service facade and ChatTuning', () {
    final original = ChatService.sendGap;
    addTearDown(() => ChatService.sendGap = original);
    ChatService.sendGap = Duration.zero;
    expect(ChatTuning.sendGap, Duration.zero);
    ChatTuning.sendGap = const Duration(milliseconds: 23);
    expect(ChatService.sendGap, const Duration(milliseconds: 23));
  });
}
