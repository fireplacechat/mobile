import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/model/notifications/preview_diagnostics.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';

class PreviewDiagnosticsScreen extends ConsumerWidget {
  const PreviewDiagnosticsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: UiAppBar(
      context: context,
      title: const Text('Preview test results'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(previewDiagnosticRunsProvider),
        ),
      ],
    ),
    body: UiPageScroll(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Local test results only. Target: peak at most about 12 MB and completion under 5 seconds. '
            'The peak is for the extension process, which iOS may reuse. '
            'An incomplete run may have stopped before recording its result.',
          ),
        ),
        ...ref
            .watch(previewDiagnosticRunsProvider)
            .when(
              loading: () => const [Center(child: CircularProgressIndicator())],
              error: (_, _) => const [
                ListTile(title: Text('Could not read local test results.')),
              ],
              data: (runs) => [
                if (runs.isEmpty)
                  const ListTile(title: Text('No preview runs recorded yet.')),
                for (final run in runs.reversed)
                  ListTile(
                    title: Text(
                      '${switch (run.outcome) {
                        PreviewRunOutcome.incomplete => 'Incomplete',
                        PreviewRunOutcome.preview => 'Preview',
                        PreviewRunOutcome.fallback => 'Fallback',
                        PreviewRunOutcome.timeout => 'Timed out',
                      }} · ${run.peakBytes == 0 ? 'Memory unavailable' : '${(run.peakBytes / (1024 * 1024)).toStringAsFixed(2)} MB'} · ${run.elapsedMillis} ms',
                    ),
                    subtitle: Text(
                      run.at.toLocal().toString().split('.').first,
                    ),
                  ),
              ],
            ),
      ],
    ),
  );
}
