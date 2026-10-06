import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/chat_summary.dart';

class ChatDirectory {
  ChatDirectory(this._db, this._messages, this.uid, this._safety);

  final FirebaseFirestore _db;
  final LocalMessageStore _messages;
  final SafetyService? _safety;
  final String uid;

  static String chatIdFor(String a, String b) {
    final s = [a, b]..sort();
    return '${s[0]}_${s[1]}';
  }

  String peerOf(String chatId) {
    final parts = chatId.split('_');
    if (parts.length != 2 || !parts.contains(uid)) {
      throw ChatException('Not a chat of this user.');
    }
    return parts[0] == uid ? parts[1] : parts[0];
  }

  // ------------------------------------------------------------------- chats

  /// Finds a user by username and makes sure the chat document exists.
  Future<String> startChat(String username) async {
    final name = username.trim().toLowerCase();
    final u = await _db.collection('usernames').doc(name).get();
    if (!u.exists) throw ChatException('No user named "$name".');
    final peerUid = u.data()!['uid'] as String;
    if (peerUid == uid) throw ChatException('You cannot chat with yourself.');
    if (_safety?.isBlocked(peerUid) ?? false) {
      throw ChatException(
        'You blocked @$name. Unblock them in Settings to chat again.',
      );
    }
    final chatId = chatIdFor(uid, peerUid);
    final ref = _db.collection('chats').doc(chatId);
    if (!(await ref.get()).exists) {
      try {
        await ref.set({
          'participants': [uid, peerUid]..sort(),
          'initiator': uid,
          'accepted': false,
          'requestCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw ChatException('You cannot start a chat with @$name.');
        }
        rethrow;
      }
    }
    return chatId;
  }

  /// Accept a message request (the recipient only).
  Future<void> acceptRequest(String chatId) async {
    peerOf(chatId);
    await _db.collection('chats').doc(chatId).update({
      'accepted': true,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<ChatSummary>> watchChats() => _db
      .collection('chats')
      .where('participants', arrayContains: uid)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            ChatSummary(
              d.id,
              peerOf(d.id),
              (d.data()['lastMessageAt'] as Timestamp?)?.toDate(),
              initiator: d.data()['initiator'] as String?,
              accepted: (d.data()['accepted'] as bool?) ?? true,
              requestCount: (d.data()['requestCount'] as int?) ?? 0,
            ),
        ],
      );

  /// When the other person deleted their account, drop the conversation: delete
  /// what I sent, the chat document (allowed by the rules once their profile is
  /// gone) and the local copy. Returns true if the chat was removed.
  Future<bool> removeChatIfPeerDeleted(String chatId) async {
    final peer = peerOf(chatId);
    if ((await _db.collection('users').doc(peer).get()).exists) return false;
    final msgs = _db.collection('chats').doc(chatId).collection('messages');
    while (true) {
      final batchDocs = await msgs
          .where('senderUid', isEqualTo: uid)
          .limit(400)
          .get();
      if (batchDocs.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in batchDocs.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await _db.collection('chats').doc(chatId).delete();
    await _messages.deleteChat(chatId);
    return true;
  }

  Future<String?> usernameOf(String peerUid) async =>
      (await _db.collection('users').doc(peerUid).get()).data()?['username']
          as String?;
}
