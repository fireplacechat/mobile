import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/view/groups/contact_picker.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// Names a new group and picks who to invite. People are invited, not added:
/// each one joins only after accepting. Pops with the new group's id.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});
  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _name = TextEditingController();
  Set<String> _picked = const {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready =>
      _name.text.trim().isNotEmpty && _picked.isNotEmpty && !_busy;

  Future<void> _create() async {
    final service = ref.read(groupServiceProvider);
    if (service == null || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final gid = await service.create(_name.text.trim(), _picked.toList());
      if (mounted) Navigator.of(context).pop(gid);
    } on GroupRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GroupActionError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not create the group. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(groupContactsProvider);
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        title: const Text('New group'),
        actions: [
          TextButton(
            key: const Key('createGroup'),
            onPressed: _ready ? _create : null,
            child: const Text('Create'),
          ),
        ],
      ),
      body: UiPageScroll(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('groupName'),
              controller: _name,
              maxLength: GroupLimits.maxNameChars,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Group name'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: UiActionError(message: _error!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Invite people you chat with (up to '
              '${GroupLimits.maxMembers - 1}). They join once they accept.',
            ),
          ),
          if (contacts.isEmpty)
            const UiEmptyState(
              title: 'No one to invite yet',
              message: 'Start a chat with someone first, then make a group.',
              icon: Icons.group_add_outlined,
            )
          else
            ContactPicker(
              contacts: contacts,
              selected: _picked,
              limit: GroupLimits.maxMembers - 1,
              onChanged: (s) => setState(() => _picked = s),
            ),
        ],
      ),
    );
  }
}
