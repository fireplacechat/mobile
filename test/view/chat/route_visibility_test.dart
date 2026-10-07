import 'package:fireplace/src/model/chat/chat_visibility.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat/route_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingVisibility extends Fake implements ChatVisibility {
  String? visible;
  final cleared = <String>[];
  @override
  void show(String? id) => visible = id;
  @override
  void clearIf(String id) {
    cleared.add(id);
    if (visible == id) visible = null;
  }
}

class CurrentRoute extends Fake implements ModalRoute<void> {
  bool current = true;
  @override
  bool get isCurrent => current;
}

void main() {
  testWidgets(
    'visibility follows current route and foreground and marks seen only when visible',
    (t) async {
      await t.pumpWidget(const SizedBox());
      final notifier = RecordingVisibility();
      final route = CurrentRoute();
      var seen = 0;
      final visibility = RouteVisibility(
        chatId: () => 'alice_fred',
        notifier: notifier,
        currentlyVisible: () => notifier.visible,
        isMounted: () => true,
        onVisible: () => seen++,
      );
      addTearDown(visibility.dispose);
      visibility.subscribe(route);
      t.binding.scheduleFrame();
      await t.pump();
      expect(notifier.visible, 'alice_fred');
      expect(seen, 1);
      expect(visibility.isCurrentRoute, isTrue);
      visibility.didChangeAppLifecycleState(AppLifecycleState.paused);
      t.binding.scheduleFrame();
      await t.pump();
      expect(visibility.foreground, isFalse);
      expect(notifier.visible, isNull);
      expect(seen, 1);
      visibility.didChangeAppLifecycleState(AppLifecycleState.resumed);
      t.binding.scheduleFrame();
      await t.pump();
      expect(notifier.visible, 'alice_fred');
      expect(seen, 2);
      route.current = false;
      visibility.didPushNext();
      t.binding.scheduleFrame();
      await t.pump();
      expect(notifier.visible, isNull);
      notifier.show('alice_bob');
      visibility.didPop();
      t.binding.scheduleFrame();
      await t.pump();
      expect(notifier.visible, 'alice_bob');
      route.current = true;
      visibility.didPopNext();
      t.binding.scheduleFrame();
      await t.pump();
      expect(notifier.visible, 'alice_fred');
      expect(seen, 3);
    },
  );
  testWidgets(
    'repeated subscription does not emit and changing routes unsubscribes the old one',
    (t) async {
      await t.pumpWidget(const SizedBox());
      final notifier = RecordingVisibility();
      final route = CurrentRoute();
      final next = CurrentRoute();
      var seen = 0;
      final visibility = RouteVisibility(
        chatId: () => 'alice_fred',
        notifier: notifier,
        currentlyVisible: () => notifier.visible,
        isMounted: () => true,
        onVisible: () => seen++,
      );
      addTearDown(visibility.dispose);
      visibility.subscribe(route);
      t.binding.scheduleFrame();
      await t.pump();
      visibility.subscribe(route);
      t.binding.scheduleFrame();
      await t.pump();
      expect(seen, 1);
      visibility.subscribe(next);
      t.binding.scheduleFrame();
      await t.pump();
      expect(seen, 2);
      chatRouteObserver.didPop(CurrentRoute(), route);
      t.binding.scheduleFrame();
      await t.pump();
      expect(seen, 2);
      chatRouteObserver.didPop(CurrentRoute(), next);
      t.binding.scheduleFrame();
      await t.pump();
      expect(seen, 3);
    },
  );
  testWidgets(
    'disposal unsubscribes observers and clears the captured chat only after the frame',
    (t) async {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpWidget(const SizedBox());
      final notifier = RecordingVisibility();
      final route = CurrentRoute();
      var id = 'alice_fred';
      var seen = 0;
      final visibility = RouteVisibility(
        chatId: () => id,
        notifier: notifier,
        currentlyVisible: () => notifier.visible,
        isMounted: () => true,
        onVisible: () => seen++,
      );
      visibility.start();
      expect(visibility.foreground, isTrue);
      visibility.subscribe(route);
      t.binding.scheduleFrame();
      await t.pump();
      visibility.dispose();
      id = 'alice_bob';
      expect(notifier.visible, 'alice_fred');
      expect(notifier.cleared, isEmpty);
      chatRouteObserver.didPop(CurrentRoute(), route);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.scheduleFrame();
      await t.pump();
      expect(seen, 1);
      expect(notifier.cleared, ['alice_fred']);
      expect(notifier.visible, isNull);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
  testWidgets(
    'queued visibility after unmount clears only the current chat with no visible callback',
    (t) async {
      var mounted = true;
      await t.pumpWidget(const SizedBox());
      final notifier = RecordingVisibility();
      var seen = 0;
      final visibility = RouteVisibility(
        chatId: () => 'alice_fred',
        notifier: notifier,
        currentlyVisible: () => notifier.visible,
        isMounted: () => mounted,
        onVisible: () => seen++,
      );
      addTearDown(visibility.dispose);
      visibility.didPush();
      mounted = false;
      notifier.show('alice_bob');
      t.binding.scheduleFrame();
      await t.pump();
      expect(notifier.visible, 'alice_bob');
      expect(notifier.cleared, ['alice_fred']);
      expect(seen, 0);
    },
  );
}
