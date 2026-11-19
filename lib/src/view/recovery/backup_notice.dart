import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/recovery/recovery_key_screen.dart';
import 'package:fireplace/src/widgets/status.dart';

/// Asks for a recovery key, on the chat list only (issue 201): it used to be
/// a banner over every page. Later hides it until the app is opened again.
class BackupNotice extends ConsumerStatefulWidget {
  const BackupNotice({super.key});
  @override
  ConsumerState<BackupNotice> createState() => _BackupNoticeState();
}

class _BackupNoticeState extends ConsumerState<BackupNotice> {
  bool _later = false;

  @override
  Widget build(BuildContext context) {
    if (_later || ref.watch(hasBackupProvider).value != false) {
      return const SizedBox.shrink();
    }
    return UiNotice(
      key: const Key('backupNotice'),
      warning: true,
      text:
          'Create a recovery key so you can restore your account if you lose '
          'this phone.',
      actions: [
        TextButton(
          key: const Key('backupLater'),
          onPressed: () => setState(() => _later = true),
          child: const Text('Later'),
        ),
        TextButton(
          key: const Key('backupCreate'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const RecoveryKeyScreen()),
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
