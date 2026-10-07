import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/chat/memory_pending.dart';
import 'package:fireplace/src/model/chat/message_recovery_action.dart';

class SendController extends ChangeNotifier {
  SendController({
    required this.chatId,
    required this.chat,
    required this.ownerUid,
    required this.pendingSends,
    required this.draft,
    required this.draftRevision,
    required this.clearDraft,
    required void Function(String) notice,
    required this.showNewest,
    required this.reviewIdentity,
    required this.identityAlerts,
    required this.confirmSendAnotherCopy,
  }) {
    _notice = notice;
  }
  final String Function() chatId;
  final ChatService? Function() chat;
  final String? Function() ownerUid;
  final PendingLocalSends Function() pendingSends;
  final String Function() draft;
  final int Function() draftRevision;
  final void Function() clearDraft;
  late final void Function(String) _notice;
  final void Function() showNewest;
  final Future<void> Function(String, List<int>) reviewIdentity;
  final Map<String, List<int>> Function() identityAlerts;
  final Future<bool?> Function() confirmSendAnotherCopy;
  bool _disposed = false;
  bool _sending = false;

  /// Messages whose outcome could not be saved in the on-device history (the storage itself
  /// failed), so the warning lives in memory only. Keyed by the server message id.
  final Map<String, MemoryPending> _memoryPending = {};
  final _messageActions = <String, MessageRecoveryAction>{};
  String? _sendError;
  final Map<String, String> _checkNote = {};
  bool get sending => _sending;
  String? get sendError => _sendError;
  Map<String, MemoryPending> get memoryPending =>
      UnmodifiableMapView(_memoryPending);
  Map<String, MessageRecoveryAction> get messageActions =>
      UnmodifiableMapView(_messageActions);
  Map<String, String> get checkNote => UnmodifiableMapView(_checkNote);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void notice(String m) {
    if (_disposed) return;
    _notice(m);
  }

  void dismissError() {
    _sendError = null;
    _changed();
  }

  void clearMemoryPending() {
    _memoryPending.clear();
  }

  void dropMemoryPending(String id) {
    _memoryPending.remove(id);
  }

  void rememberMemoryPending(String id, MemoryPending Function() create) {
    _memoryPending.putIfAbsent(id, create);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> send() async {
    if (messageTooLong(draft())) {
      _sendError = messageLimitError;
      _changed();
      return;
    }
    final body = draft().trim();
    final service = chat();
    final uid = ownerUid();
    if (body.isEmpty || service == null || _sending) return;
    final peerUid = service.peerOf(chatId());
    if (identityAlerts().containsKey(peerUid)) {
      notice('Review the security code change before sending.');
      return;
    }
    final draftRevision = this.draftRevision();
    _sending = true;
    _sendError = null;
    _changed();
    try {
      await service.sendText(chatId(), body);
      if (_disposed) return;
      if (this.draftRevision() == draftRevision) clearDraft();
      showNewest();
    } on SendNotConfirmedException catch (e) {
      // The message may already have been delivered, so this is NOT a plain failure: the attempted
      // draft moves into a pending bubble (warning below it) instead of staying poised to resend.
      if (_disposed) return;
      if (!e.persisted) {
        pendingSends().add(e, ownerUid: uid!);
        _memoryPending[e.messageId] = MemoryPending(e);
        _changed();
      }
      // Edits made while the send was in flight survive: only an untouched draft is cleared.
      if (this.draftRevision() == draftRevision) clearDraft();
      showNewest();
    } on IdentityChangedException catch (e) {
      if (!_disposed) await reviewIdentity(e.peerUid, e.newIdentityPub);
    } on ChatException catch (e) {
      if (!_disposed) {
        _sendError = e.message;
        _changed();
      }
    } catch (_) {
      if (!_disposed) {
        _sendError = 'We could not confirm this send. It may have reached them. Check your history before sending again.';
        _changed();
      }
    } finally {
      if (!_disposed) {
        _sending = false;
        _changed();
      }
    }
  }

  void forgetPending(String id) {
    _memoryPending.remove(id);
    pendingSends().remove(chatId(), id);
  }

  /// Asks the server whether the message exists. Never publishes anything.
  Future<void> checkStatus(String messageId) async {
    final service = chat();
    final uid = ownerUid();
    if (service == null || _messageActions.containsKey(messageId)) return;
    _messageActions[messageId] = MessageRecoveryAction.checking;
    _checkNote.remove(messageId);
    _changed();
    try {
      final outcome = await service.checkSendStatus(chatId(), messageId);
      if (_disposed) return;
      if (outcome == SendOutcome.confirmed) {
        final mem = _memoryPending[messageId];
        if (mem != null) {
          mem.outcome = SendOutcome.publishedLocalSaveFailed;
          pendingSends().confirmed(chatId(), messageId, ownerUid: uid!);
          try {
            await service.saveSentLocally(
              chatId: chatId(),
              messageId: messageId,
              body: mem.body,
              sentAt: mem.sentAt,
            );
            forgetPending(messageId);
          } catch (_) {
            // Still held in memory; the message is confirmed on the server.
          }
        }
        notice('Message confirmed: it reached the server.');
      } else {
        _checkNote[messageId] =
            'Still not sure. It may or may not have been delivered.';
        _changed();
      }
    } catch (_) {
      if (!_disposed) {
        _checkNote[messageId] =
            'Could not check yet. Nothing was sent again. Try later.';
        _changed();
      }
    } finally {
      if (!_disposed) {
        _messageActions.remove(messageId);
        _changed();
      }
    }
  }

  /// The explicit "send another copy" decision.
  Future<void> sendAgain(String messageId, String body) async {
    final service = chat();
    final uid = ownerUid();
    if (service == null || _messageActions.containsKey(messageId)) return;
    _messageActions[messageId] = MessageRecoveryAction.resending;
    _changed();
    try {
      final go = await confirmSendAnotherCopy();
      if (go != true || _disposed) return;
      await service.resendUnconfirmed(
        chatId: chatId(),
        messageId: messageId,
        body: body,
      );
      if (!_disposed) {
        forgetPending(messageId);
        _changed();
      }
    } on SendNotConfirmedException catch (e) {
      if (!_disposed && !e.persisted) {
        pendingSends().add(e, ownerUid: uid!);
        _memoryPending[e.messageId] = MemoryPending(e);
        _changed();
      }
    } on ChatException catch (e) {
      if (!_disposed) {
        _checkNote[messageId] = e.message;
        _changed();
      }
    } catch (_) {
      if (!_disposed) {
        _checkNote[messageId] = 'The new copy is not confirmed. It may have reached them. Do not send another copy without checking.';
        _changed();
      }
    } finally {
      if (!_disposed) {
        _messageActions.remove(messageId);
        _changed();
      }
    }
  }

  /// Repairs local history for a message known to be on the server. No publish.
  Future<void> saveOnDevice(MemoryPending mem) async {
    final service = chat();
    if (service == null || _messageActions.containsKey(mem.messageId)) return;
    _messageActions[mem.messageId] = MessageRecoveryAction.saving;
    _changed();
    try {
      await service.saveSentLocally(
        chatId: chatId(),
        messageId: mem.messageId,
        body: mem.body,
        sentAt: mem.sentAt,
      );
      if (!_disposed) {
        forgetPending(mem.messageId);
        _changed();
      }
    } catch (_) {
      if (!_disposed) {
        _checkNote[mem.messageId] = 'Could not save on this device yet. Your message was sent: do not send it again.';
        _changed();
      }
    } finally {
      if (!_disposed) {
        _messageActions.remove(mem.messageId);
        _changed();
      }
    }
  }
}
