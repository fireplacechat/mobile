import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pacing is shared between the service facade and ChatTuning', () {
    final original = ChatService.pacing;
    addTearDown(() => ChatService.pacing = original);
    ChatService.pacing = true;
    expect(ChatTuning.pacing, isTrue);
    ChatTuning.pacing = false;
    expect(ChatService.pacing, isFalse);
  });
}
