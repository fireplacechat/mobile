import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const area = Rect.fromLTRB(16, 60, 359, 778);

  test('a message with room keeps its place', () {
    const anchor = Rect.fromLTWH(16, 300, 180, 70);
    final placed = placeMessageMenu(
      area: area,
      anchor: anchor,
      preview: anchor.size,
      reactions: const Size(320, 56),
      menu: const Size(250, 200),
      alignEnd: false,
    );
    expect(placed.scale, 1);
    expect(placed.preview, anchor);
    expect(placed.reactions!.top, anchor.top - 12 - 56);
    expect(placed.reactions!.left, anchor.left);
    expect(placed.menu.top, anchor.bottom + 12);
    expect(placed.menu.left, anchor.left);
    expect(placed.menu.bottom, lessThan(area.bottom));
  });

  test('an outgoing message hangs the bar and the list from the right', () {
    const anchor = Rect.fromLTWH(179, 300, 180, 70);
    final placed = placeMessageMenu(
      area: area,
      anchor: anchor,
      preview: anchor.size,
      reactions: const Size(320, 56),
      menu: const Size(250, 200),
      alignEnd: true,
    );
    expect(placed.preview.right, anchor.right);
    expect(placed.reactions!.right, anchor.right);
    expect(placed.menu.right, anchor.right);
  });

  test('a message that is too low rises until the list meets the bottom', () {
    const anchor = Rect.fromLTWH(16, 700, 180, 70);
    final placed = placeMessageMenu(
      area: area,
      anchor: anchor,
      preview: anchor.size,
      reactions: const Size(320, 56),
      menu: const Size(250, 200),
      alignEnd: false,
    );
    expect(placed.scale, 1);
    expect(placed.preview.top, lessThan(anchor.top));
    expect(placed.menu.bottom, area.bottom);
    expect(placed.menu.top - placed.preview.bottom, 12);
    expect(placed.reactions!.bottom, placed.preview.top - 12);
  });

  test('a message that still does not fit scales down from its edge', () {
    const anchor = Rect.fromLTWH(16, 400, 180, 900);
    final placed = placeMessageMenu(
      area: area,
      anchor: anchor,
      preview: anchor.size,
      reactions: const Size(320, 56),
      menu: const Size(250, 350),
      alignEnd: false,
    );
    expect(placed.scale, lessThan(1));
    expect(placed.scale, greaterThanOrEqualTo(0.1));
    expect(placed.preview.left, anchor.left);
    expect(placed.reactions!.top, greaterThanOrEqualTo(area.top));
    expect(placed.menu.bottom, lessThanOrEqualTo(area.bottom));
    expect(placed.preview.height, closeTo(900 * placed.scale, .01));
  });

  test('landscape puts the list beside the message', () {
    const wide = Rect.fromLTRB(16, 16, 800, 360);
    const anchor = Rect.fromLTWH(16, 80, 180, 60);
    final placed = placeMessageMenu(
      area: wide,
      anchor: anchor,
      preview: anchor.size,
      reactions: const Size(320, 56),
      menu: const Size(250, 200),
      alignEnd: false,
      menuBeside: true,
    );
    expect(placed.scale, 1);
    expect(placed.menu.left, placed.preview.right + 12);
    expect(placed.menu.top, placed.preview.top);
    expect(placed.reactions!.bottom, placed.preview.top - 12);
  });

  test('a finger inside the dead zone cannot highlight a control', () {
    final gesture = MessageMenuGesture()..origin = Offset.zero;
    addTearDown(gesture.dispose);
    expect(gesture.allowsHighlight(const Offset(10, 0)), isFalse);
    expect(gesture.armed, isFalse);
    expect(gesture.allowsHighlight(const Offset(40, 0)), isTrue);
    expect(gesture.armed, isTrue);
    expect(gesture.allowsHighlight(Offset.zero), isTrue);
  });
}
