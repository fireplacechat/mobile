import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/widgets/avatar.dart';

/// A tickable list of contacts, used to start a group and to add people.
class ContactPicker extends ConsumerWidget {
  const ContactPicker({
    super.key,
    required this.contacts,
    required this.selected,
    required this.onChanged,
    required this.limit,
  });
  final List<String> contacts;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// How many may be ticked; further rows are disabled once it is reached.
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final uid in contacts)
          Builder(
            builder: (context) {
              final name = ref.watch(peerUsernameProvider(uid)).value ?? '…';
              final ticked = selected.contains(uid);
              return CheckboxListTile(
                key: Key('pick_$uid'),
                value: ticked,
                secondary: PersonAvatar(name: name, size: 36),
                title: Text('@$name'),
                onChanged: !ticked && selected.length >= limit
                    ? null
                    : (on) => onChanged(
                        on == true
                            ? {...selected, uid}
                            : ({...selected}..remove(uid)),
                      ),
              );
            },
          ),
      ],
    );
  }
}
