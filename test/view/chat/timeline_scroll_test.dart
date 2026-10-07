import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> attach(WidgetTester t, TimelineScroll timeline) => t.pumpWidget(
  MaterialApp(
    home: SizedBox(
      height: 200,
      child: ListView(
        controller: timeline.controller,
        children: const [SizedBox(height: 2000)],
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'away threshold notifies once per transition and never for unchanged offset state',
    (t) async {
      final timeline = TimelineScroll(isMounted: () => true);
      addTearDown(timeline.dispose);
      var changes = 0;
      timeline.addListener(() => changes++);
      await attach(t, timeline);
      timeline.controller.jumpTo(96);
      expect(timeline.awayFromLatest, isFalse);
      expect(changes, 0);
      timeline.controller.jumpTo(97);
      expect(timeline.awayFromLatest, isTrue);
      expect(changes, 1);
      timeline.controller.jumpTo(300);
      expect(changes, 1);
      timeline.controller.jumpTo(96);
      expect(timeline.awayFromLatest, isFalse);
      expect(changes, 2);
      await t.pumpWidget(const SizedBox());
    },
  );
  test('anchor cache reuses keys and prunes silently', () {
    final timeline = TimelineScroll(isMounted: () => true);
    addTearDown(timeline.dispose);
    var changes = 0;
    timeline.addListener(() => changes++);
    final first = timeline.anchorFor('first');
    final second = timeline.anchorFor('second');
    expect(timeline.anchorFor('first'), same(first));
    timeline.pruneAnchors({'second'});
    expect(timeline.anchorFor('second'), same(second));
    expect(timeline.anchorFor('first'), isNot(same(first)));
    expect(changes, 0);
  });
  testWidgets('reduced motion jumps and normal motion animates over 180 ms', (
    t,
  ) async {
    final timeline = TimelineScroll(isMounted: () => true);
    addTearDown(timeline.dispose);
    await attach(t, timeline);
    timeline.controller.jumpTo(300);
    timeline.scrollToLatest(reduceMotion: true);
    expect(timeline.controller.offset, 0);
    timeline.controller.jumpTo(300);
    timeline.scrollToLatest(reduceMotion: false);
    expect(timeline.controller.offset, 300);
    t.binding.scheduleFrame();
    await t.pump();
    await t.pump(const Duration(milliseconds: 90));
    expect(timeline.controller.offset, greaterThan(0));
    expect(timeline.controller.offset, lessThan(300));
    await t.pump(const Duration(milliseconds: 90));
    expect(timeline.controller.offset, 0);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('near-bottom jump respects 96 threshold', (t) async {
    final timeline = TimelineScroll(isMounted: () => true);
    addTearDown(timeline.dispose);
    await attach(t, timeline);
    timeline.controller.jumpTo(97);
    timeline.jumpToLatestIfNear();
    expect(timeline.controller.offset, 97);
    timeline.controller.jumpTo(96);
    timeline.jumpToLatestIfNear();
    expect(timeline.controller.offset, 0);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'own-send callback is deferred and suppressed after unmount or dispose',
    (t) async {
      await t.pumpWidget(const SizedBox());
      var mounted = true;
      final timeline = TimelineScroll(isMounted: () => mounted);
      var calls = 0;
      timeline.showNewestAfterOwnSend(() => calls++);
      expect(calls, 0);
      t.binding.scheduleFrame();
      await t.pump();
      expect(calls, 1);
      timeline.showNewestAfterOwnSend(() => calls++);
      mounted = false;
      t.binding.scheduleFrame();
      await t.pump();
      expect(calls, 1);
      mounted = true;
      timeline.showNewestAfterOwnSend(() => calls++);
      timeline.keepReadingAnchor((GlobalKey(), 10));
      timeline.dispose();
      timeline.scrollToLatest(reduceMotion: true);
      timeline.jumpToLatestIfNear();
      t.binding.scheduleFrame();
      await t.pump();
      expect(calls, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('detached timeline and absent reading anchor are harmless', (
    t,
  ) async {
    final timeline = TimelineScroll(isMounted: () => true);
    addTearDown(timeline.dispose);
    expect(timeline.readingAnchor(), isNull);
    timeline.scrollToLatest(reduceMotion: false);
    timeline.jumpToLatestIfNear();
    timeline.keepReadingAnchor((GlobalKey(), 10));
    t.binding.scheduleFrame();
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
