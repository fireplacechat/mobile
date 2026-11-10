import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

bool sameLocalDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

class DaySeparator extends StatelessWidget {
  const DaySeparator({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final label = MaterialLocalizations.of(context)
        .formatMediumDate(date.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A flex share is only a third of the row, which wraps
          // "Tue, Nov 10". The label keeps its own width and scales
          // down only when one line would leave the rules with nothing.
          const gap = 12.0;
          const minLine = 12.0;
          final room = constraints.maxWidth - gap * 2 - minLine * 2;
          final maxChip = room < 0 ? 0.0 : room;
          return Row(
            children: [
              const Expanded(child: Divider()),
              const SizedBox(width: gap),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxChip),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: FireplaceUiTokens.of(context).panel,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: gap),
              const Expanded(child: Divider()),
            ],
          );
        },
      ),
    );
  }
}
