import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';

class ThemeScreen extends ConsumerStatefulWidget {
  const ThemeScreen({super.key});

  @override
  ConsumerState<ThemeScreen> createState() => _ThemeScreenState();
}

class _ThemeScreenState extends ConsumerState<ThemeScreen> {
  bool _saving = false;

  Future<void> _save(ThemeMode mode) async {
    // A tap on the selected preview still replaces a legacy System preference.
    if (_saving || ref.read(themeModeProvider).value == mode) return;
    setState(() => _saving = true);
    try {
      await ref.read(themeModeProvider.notifier).setMode(mode);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not save your theme. Try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(themeModeProvider);
    final mode = preference.value ?? ThemeMode.system;
    final selected = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => Theme.of(context).brightness,
    };
    final choices = [
      for (final brightness in [Brightness.light, Brightness.dark])
        _ThemeChoice(
          brightness: brightness,
          selected: selected == brightness,
          onTap: _saving || preference.isLoading
              ? null
              : () => _save(
                  brightness == Brightness.light
                      ? ThemeMode.light
                      : ThemeMode.dark,
                ),
        ),
    ];
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Theme')),
      body: UiPageScroll(
        children: [
          Text(
            'Choose your theme',
            textAlign: TextAlign.start,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a look for this device.',
            textAlign: TextAlign.start,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: FireplaceUiTokens.of(context).secondaryText),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: choices[0]),
              const SizedBox(width: 14),
              Expanded(child: choices[1]),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  final Brightness brightness;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final dark = brightness == Brightness.dark;
    final label = dark ? 'Dark' : 'Light';
    return Semantics(
      key: ValueKey('theme-${brightness.name}'),
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: '$label theme',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              key: ValueKey('theme-preview-${brightness.name}'),
              padding: const EdgeInsets.all(4),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? t.accent : t.separator,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LayoutBuilder(
                  builder: (context, box) => SizedBox(
                    width: double.infinity,
                    // Preserve phone proportions; cap tablet height.
                    height: (box.maxWidth * 250 / 152.5).clamp(0, 320),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: 375,
                        height: 625,
                        // Use the real splash artwork without its animation.
                        child: ColoredBox(
                          color: dark ? fireplaceCharcoal : fireplaceCream,
                          child: Center(
                            child: FireplaceLockup(
                              wordmarkColor: dark
                                  ? fireplaceWordmarkOnCharcoal
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
