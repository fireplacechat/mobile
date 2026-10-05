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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        const Expanded(child: Divider()),
        const SizedBox(width: 12),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FireplaceUiTokens.of(context).panel,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              MaterialLocalizations.of(context)
                  .formatMediumDate(date.toLocal()),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider()),
      ],
    ),
  );
}
