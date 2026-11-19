import 'package:fireplace/src/widgets/swipe_back_route.dart';
import 'package:flutter/material.dart';

/// Conversations reached from Requests also support the Android back drag.
PageRoute<void> requestConversationRoute(BuildContext context, Widget screen) =>
    Theme.of(context).platform == TargetPlatform.android
    ? SwipeBackPageRoute<void>(builder: (_) => screen)
    : MaterialPageRoute<void>(builder: (_) => screen);
