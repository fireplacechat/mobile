import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const previewDiagnosticsEnabled =
    kDebugMode || bool.fromEnvironment('PREVIEW_DIAGNOSTICS');

enum PreviewRunOutcome { incomplete, preview, fallback, timeout }

class PreviewDiagnosticRun {
  const PreviewDiagnosticRun({
    required this.at,
    required this.elapsedMillis,
    required this.peakBytes,
    required this.outcome,
  });
  final DateTime at;
  final int elapsedMillis, peakBytes;
  final PreviewRunOutcome outcome;

  static PreviewDiagnosticRun? parse(Map<dynamic, dynamic> json) {
    final at = json['at'],
        ms = json['ms'],
        peak = json['peak'],
        outcome = json['outcome'];
    if (at is! int ||
        at <= 0 ||
        at > 8640000000000000 ||
        ms is! int ||
        ms < 0 ||
        ms > 60000 ||
        peak is! int ||
        peak < 0 ||
        peak > 512 * 1024 * 1024 ||
        outcome is! int ||
        outcome < 0 ||
        outcome > 3) {
      return null;
    }
    return PreviewDiagnosticRun(
      at: DateTime.fromMillisecondsSinceEpoch(at),
      elapsedMillis: ms,
      peakBytes: peak,
      outcome: PreviewRunOutcome.values[outcome],
    );
  }
}

final previewDiagnosticRunsProvider =
    FutureProvider<List<PreviewDiagnosticRun>>((ref) async {
      if (!previewDiagnosticsEnabled) return const [];
      const channel = MethodChannel('fireplace/notifications');
      final rows =
          await channel.invokeListMethod<dynamic>('previewDiagnostics') ??
          const [];
      return [
        for (final row in rows.take(20))
          if (row is Map) ?PreviewDiagnosticRun.parse(row),
      ];
    });
