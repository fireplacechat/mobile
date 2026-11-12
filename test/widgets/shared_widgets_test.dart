import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/settings_section.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

Future<void> pump(WidgetTester t, UiFixture f, Widget child) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('an empty state shows its words and runs its button', (t) async {
    final f = UiFixture();
    await f.seed();
    var taps = 0;
    await pump(
      t,
      f,
      UiEmptyState(
        title: 'No conversations yet',
        message: 'Start one when you are ready.',
        action: TextButton(onPressed: () => taps++, child: const Text('Start')),
      ),
    );
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.text('Start one when you are ready.'), findsOneWidget);
    await t.tap(find.text('Start'));
    expect(taps, 1);
  });

  testWidgets('an action error shows the plain message', (t) async {
    final f = UiFixture();
    await f.seed();
    await pump(
      t,
      f,
      const UiActionError(message: 'Could not save. Try again.'),
    );
    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets(
    'a warning notice shows its text and a disabled button stays off',
    (t) async {
      final f = UiFixture();
      await f.seed();
      var taps = 0;
      await pump(
        t,
        f,
        UiNotice(
          text: 'This phone is offline.',
          warning: true,
          actions: [
            TextButton(onPressed: () => taps++, child: const Text('Try again')),
            const TextButton(onPressed: null, child: Text('Wait')),
          ],
        ),
      );
      expect(find.text('This phone is offline.'), findsOneWidget);
      await t.tap(find.text('Try again'));
      expect(taps, 1);
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, 'Wait')).onPressed,
        isNull,
      );
    },
  );

  testWidgets('a dialog shows its title and runs its button', (t) async {
    final f = UiFixture();
    await f.seed();
    var taps = 0;
    await pump(
      t,
      f,
      UiDialog(
        title: const Text('Remove this device?'),
        content: const Text('It will need to be linked again.'),
        actions: [
          TextButton(onPressed: () => taps++, child: const Text('Remove')),
        ],
      ),
    );
    expect(find.text('Remove this device?'), findsOneWidget);
    expect(find.text('It will need to be linked again.'), findsOneWidget);
    await t.tap(find.text('Remove'));
    expect(taps, 1);
  });

  testWidgets('a status and a settings section show their labels', (t) async {
    final f = UiFixture();
    await f.seed();
    await pump(
      t,
      f,
      const Column(
        children: [
          UiStatus(label: 'Saved on this phone', icon: Icons.check),
          UiSettingsSection(
            title: 'Notifications',
            children: [Text('Show message preview')],
          ),
        ],
      ),
    );
    expect(find.text('Saved on this phone'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Show message preview'), findsOneWidget);
  });
}
