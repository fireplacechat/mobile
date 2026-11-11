import 'package:flutter/material.dart';

import 'package:fireplace/src/view/safety/safety_action_sheet.dart';

/// Signal's block panel: "Block {name}?", the consequence, a red Block
/// capsule and Cancel.
Future<bool> confirmBlock(BuildContext context, String name) async {
  final who = name.trim().isEmpty ? 'this person' : name.trim();
  final ok = await showSafetyActionSheet<bool>(
    context: context,
    title: 'Block $who?',
    message: 'Blocked users will not be able to send you messages.',
    actions: const [
      SafetySheetAction(
        label: 'Block',
        value: true,
        style: SafetyActionStyle.destructive,
        buttonKey: Key('confirmBlock'),
      ),
      SafetySheetAction(
        label: 'Cancel',
        value: false,
        buttonKey: Key('cancelBlock'),
      ),
    ],
  );
  return ok == true;
}
