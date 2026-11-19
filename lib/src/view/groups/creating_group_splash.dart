import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// What New group shows while the group is made (issue 204): the loading
/// splash with a progress bar and "Creating" whose dots count up and start
/// again. It cannot be left: the group is being made on the server.
class CreatingGroupSplash extends StatelessWidget {
  const CreatingGroupSplash({super.key});

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: FireplaceSplash(
      status: Semantics(
        key: const Key('creatingGroup'),
        liveRegion: true,
        label: 'Creating the group',
        excludeSemantics: true,
        child: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  color: FireplaceUiTokens.of(context).accent,
                  backgroundColor: FireplaceUiTokens.of(context).separator,
                ),
              ),
              const SizedBox(height: 14),
              const CreatingDots(),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "Creating", then one, two and three dots, and round again.
class CreatingDots extends StatefulWidget {
  const CreatingDots({super.key});

  /// How long each step shows.
  static const step = Duration(milliseconds: 450);

  @override
  State<CreatingDots> createState() => _CreatingDotsState();
}

class _CreatingDotsState extends State<CreatingDots> {
  int _dots = 1;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With reduced motion the dots stay still.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _timer?.cancel();
      _timer = null;
      _dots = 3;
    } else {
      _timer ??= Timer.periodic(CreatingDots.step, (_) {
        if (mounted) setState(() => _dots = (_dots + 1) % 4);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final style = Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: t.text);
    // The missing dots keep their room, so the word does not shift.
    return Text.rich(
      key: const Key('creatingText'),
      TextSpan(
        text: 'Creating${'.' * _dots}',
        children: [
          TextSpan(
            text: '.' * (3 - _dots),
            style: const TextStyle(color: Colors.transparent),
          ),
        ],
      ),
      style: style,
    );
  }
}
