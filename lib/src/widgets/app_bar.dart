import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Enlarged titles fit normally; a nearly full-screen keyboard compacts chrome.
class UiAppBar extends AppBar {
  UiAppBar({
    super.key,
    required BuildContext context,
    Widget? title,
    super.actions,
    super.leading,
    super.centerTitle,
    double? toolbarHeight,
  }) : super(
         title:
             MediaQuery.sizeOf(context).height -
                     MediaQuery.viewInsetsOf(context).bottom <
                 160
             ? null
             : title,
         toolbarHeight: math
             .max(
               toolbarHeight ?? 64,
               MediaQuery.textScalerOf(context).scale(22) * 1.35 + 16,
             )
             .clamp(
               48,
               math.max(
                 48,
                 (MediaQuery.sizeOf(context).height -
                         MediaQuery.viewInsetsOf(context).bottom) *
                     .4,
               ),
             ),
       );
}
