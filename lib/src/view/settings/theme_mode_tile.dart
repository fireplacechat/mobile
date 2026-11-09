import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/widgets/dialog.dart';

class ThemeModeTile extends ConsumerStatefulWidget {
  const ThemeModeTile({super.key});

  @override
  ConsumerState<ThemeModeTile> createState() => _ThemeModeTileState();
}

class _ThemeModeTileState extends ConsumerState<ThemeModeTile> {
  bool _saving = false;

  Future<void> _choose(ThemeMode current) async {
    final mode = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => UiDialog(
        title: const Text('Theme'),
        content: RadioGroup<ThemeMode>(
          groupValue: current,
          onChanged: (mode) => Navigator.pop(context, mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in ThemeMode.values)
                RadioListTile<ThemeMode>(
                  key: ValueKey('theme-${mode.name}'),
                  value: mode,
                  title: Text(_label(mode)),
                  subtitle: mode == ThemeMode.system
                      ? const Text('Use your device setting')
                      : null,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || mode == null || mode == current) return;
    setState(() => _saving = true);
    try {
      await ref.read(themeModeProvider.notifier).setMode(mode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your theme. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(themeModeProvider);
    final mode = preference.value ?? ThemeMode.system;
    return ListTile(
      key: const Key('themeMode'),
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Theme'),
      subtitle: Text(_label(mode)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _saving || preference.isLoading ? null : () => _choose(mode),
    );
  }
}
