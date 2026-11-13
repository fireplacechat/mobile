import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/view/settings/theme_screen.dart';

class ThemeModeTile extends ConsumerWidget {
  const ThemeModeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(themeModeProvider);
    final mode = preference.value ?? ThemeMode.system;
    final dark = mode == ThemeMode.system
        ? Theme.of(context).brightness == Brightness.dark
        : mode == ThemeMode.dark;
    return ListTile(
      key: const Key('themeMode'),
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Theme'),
      subtitle: Text(dark ? 'Dark' : 'Light'),
      trailing: const Icon(Icons.chevron_right),
      onTap: preference.isLoading
          ? null
          : () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ThemeScreen()),
            ),
    );
  }
}
