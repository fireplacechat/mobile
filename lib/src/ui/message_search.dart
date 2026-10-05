import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../services/local_messages.dart';
import 'chat_activity.dart';
import 'chat_screen.dart';

List<MessageSearchHit> _scan((Map<String, List<LocalMessage>>, String) input) =>
    searchMessages(input.$1, input.$2);
final messageSearchProvider = FutureProvider.autoDispose
    .family<List<MessageSearchHit>, String>((ref, query) async {
      final history = ref.watch(chatActivityProvider.select((s) => s.history));
      final waiting = Completer<void>();
      final timer = Timer(const Duration(milliseconds: 250), waiting.complete);
      ref.onDispose(() {
        timer.cancel();
        if (!waiting.isCompleted) waiting.complete();
      });
      await waiting.future;
      if (!ref.mounted) return [];
      return compute(_scan, (history, query));
    });

class GlobalMessageResults extends ConsumerWidget {
  const GlobalMessageResults({
    super.key,
    required this.query,
    required this.onOpen,
  });
  final String query;
  final void Function(Widget) onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(chatActivityProvider);
    final results = ref.watch(messageSearchProvider(query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            'Messages on this device',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (activity.failed.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Some local histories could not be read. Those messages are not searched.',
            ),
          ),
        if (activity.loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Loading local history…'),
          ),
        ...results.when(
          loading: () => [
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(
                semanticsLabel: 'Searching local messages',
              ),
            ),
          ],
          error: (_, _) => [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () => ref.invalidate(messageSearchProvider(query)),
                child: const Text('Search did not finish — try again'),
              ),
            ),
          ],
          data: (hits) => [
            if (hits.isEmpty && !activity.loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No matching messages on this device.'),
              ),
            for (final hit in hits) _SearchTile(hit: hit, onOpen: onOpen),
            if (hits.length == 100)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Showing the newest 100 matches. Refine your search to find more.',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SearchTile extends ConsumerWidget {
  const _SearchTile({required this.hit, required this.onOpen});
  final MessageSearchHit hit;
  final void Function(Widget) onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(chatSummaryProvider(hit.message.chatId));
    if (summary == null ||
        !ref.read(chatActivityProvider.notifier).eligible(summary)) {
      return const SizedBox.shrink();
    }
    final name = ref.watch(peerUsernameProvider(summary.peerUid)).value ?? '…';
    // Bound snippets without splitting UTF-16 surrogate pairs.
    var start = (hit.start - 40).clamp(0, hit.text.length);
    var end = (hit.end + 80).clamp(0, hit.text.length);
    bool low(int at) =>
        at < hit.text.length &&
        hit.text.codeUnitAt(at) >= 0xdc00 &&
        hit.text.codeUnitAt(at) <= 0xdfff;
    if (low(start)) start--;
    if (low(end)) end++;
    return ListTile(
      key: ValueKey('searchHit-${hit.message.chatId}-${hit.message.id}'),
      leading: const Icon(Icons.search),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${start > 0 ? '…' : ''}${hit.text.substring(start, hit.start)}',
                ),
                TextSpan(
                  text: hit.text.substring(hit.start, hit.end),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                  ),
                ),
                TextSpan(
                  text:
                      '${hit.text.substring(hit.end, end)}${end < hit.text.length ? '…' : ''}',
                ),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            MaterialLocalizations.of(context)
                .formatMediumDate(hit.message.sentAt.toLocal()),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      onTap: () => onOpen(
        ChatScreen(
          chatId: hit.message.chatId,
          initialMessageId: hit.message.id,
        ),
      ),
    );
  }
}
