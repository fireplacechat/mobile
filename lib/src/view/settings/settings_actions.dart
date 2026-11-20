import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/common/external_browser.dart';
import 'package:fireplace/src/view/settings/browser_error_dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/settings/settings_page.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/widgets/swipe_back_route.dart';

/// A Settings page's own route: on Android it can be dragged back from
/// anywhere on the page, as the main Settings page can (issue 236).
Route<void> settingsPageRoute(BuildContext context, Widget page) =>
    Theme.of(context).platform == TargetPlatform.android
    ? SwipeBackPageRoute<void>(builder: (_) => page)
    : MaterialPageRoute<void>(builder: (_) => page);

/// One action at a time on a Settings page: rows are disabled while it
/// runs, and a failure shows a plain message at the top of the page.
mixin SettingsActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'That action did not finish. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Widget page) => run(() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  });

  Future<void> openLegal(String address) async {
    if (busy) return;
    setState(() => busy = true);
    var opened = false;
    try {
      opened = await ref.read(externalBrowserProvider).open(Uri.parse(address));
    } catch (_) {
      // Keep the rows available for retry if the browser cannot open.
    }
    if (!mounted) return;
    if (!opened) await showBrowserErrorDialog(context);
    if (mounted) setState(() => busy = false);
  }

  /// The failure message, for the top of the page.
  List<Widget> get errorRows => [
    if (error != null)
      UiActionError(key: const Key('settingsError'), message: error!),
  ];
}

/// A Settings page that needs the signed-in account: while it loads, if it
/// cannot be loaded, or after signing out, the page says so instead.
class SettingsSessionPage extends ConsumerWidget {
  const SettingsSessionPage({
    super.key,
    required this.title,
    required this.builder,
  });

  final String title;
  final List<Widget> Function(AppSession session) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    final s = session.value;
    if (s != null) return SettingsPage(title: title, children: builder(s));
    return SettingsPage(
      title: title,
      body: session.hasError
          ? UiEmptyState(
              title: 'Could not load your account',
              message: 'Try again to open Settings.',
              action: TextButton(
                onPressed: () => ref.invalidate(appSessionProvider),
                child: const Text('Try again'),
              ),
            )
          : session.isLoading
          ? const Center(child: CircularProgressIndicator())
          : const UiEmptyState(
              title: 'Sign in to view Settings',
              message: 'Go back to sign in to your account.',
            ),
    );
  }
}
