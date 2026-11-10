import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';

enum CatalogInteraction { searchEmpty, compose, sending }

class CatalogCase {
  const CatalogCase(
    this.name,
    this.screen, {
    this.overrides = const [],
    this.signup = false,
    this.interaction,
    this.size = const Size(390, 844),
    this.textScale = 1,
    this.keyboardInset = 0,
    this.prepare,
    this.services,
    this.act,
    this.overrideAuth = true,
    this.notices = false,
  });
  final void Function(UiFixture)? prepare;
  final List<Override> Function(UiFixture)? services;
  final Future<void> Function(WidgetTester, UiFixture)? act;
  final String name;
  final Widget screen;
  final List<Override> overrides;
  final bool signup, overrideAuth, notices;
  final CatalogInteraction? interaction;
  final Size size;
  final double textScale, keyboardInset;
}
