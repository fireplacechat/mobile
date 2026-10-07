import 'package:flutter/foundation.dart';

class ContactController extends ChangeNotifier {
  ContactController({required this.reviewOnce});
  final Future<void> Function(String, List<int>) reviewOnce;
  bool _contactBusy = false, _reviewing = false;
  String? _contactError;
  bool _disposed = false;
  bool get busy => _contactBusy;
  bool get reviewing => _reviewing;
  String? get error => _contactError;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Lets the user compare and explicitly decide about a changed contact key.
  /// Nothing is trusted automatically.
  Future<void> contactAction(Future<void> Function() action) async {
    if (_contactBusy) return;
    {
      _contactBusy = true;
      _contactError = null;
      _changed();
    }
    try {
      await action();
    } catch (_) {
      if (!_disposed) {
        {
          _contactError = 'Could not update this contact. Try again.';
          _changed();
        }
      }
    } finally {
      if (!_disposed) {
        _contactBusy = false;
        _changed();
      }
    }
  }

  Future<void> reviewIdentity(String peerUid, List<int> pub) async {
    if (_reviewing) return;
    {
      _reviewing = true;
      _changed();
    }
    try {
      await reviewOnce(peerUid, pub);
    } catch (_) {
      if (!_disposed) {
        {
          _contactError = 'Could not finish the security review. Check this contact’s security code before continuing. Try again.';
          _changed();
        }
      }
    } finally {
      if (!_disposed) {
        _reviewing = false;
        _changed();
      }
    }
  }
}
