import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/avatar.dart';

/// A group's avatar: its name's first letter in a circle, like a person's
/// (owner's choice, decision 0050; the first version used a rounded square).
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => PersonAvatar(
    // A group invitation has no name to show until it is joined.
    name: name.trim().isEmpty ? '#' : name.trim().characters.first,
    size: size,
  );
}
