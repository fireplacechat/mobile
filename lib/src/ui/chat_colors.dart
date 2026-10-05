import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Presentation only: no account fields, files, preferences or cloud writes.
enum ChatBubbleColor {
  ember('Ember', Color(0xFFBF5700), Color(0xFFF5E5D9), Color(0xFF50311D)),
  forest('Forest', Color(0xFF28634F), Color(0xFFE0ECE4), Color(0xFF293F35)),
  ocean('Ocean', Color(0xFF285D83), Color(0xFFE1EBF3), Color(0xFF293E50)),
  plum('Plum', Color(0xFF734A78), Color(0xFFEFE3EF), Color(0xFF453449)),
  stone('Stone', Color(0xFF59534C), Color(0xFFEFEBE5), Color(0xFF3B464D));

  const ChatBubbleColor(
    this.label,
    this.outgoing,
    this.lightIncoming,
    this.darkIncoming,
  );
  final String label;
  final Color outgoing, lightIncoming, darkIncoming;
  Color incoming(Brightness brightness) =>
      brightness == Brightness.dark ? darkIncoming : lightIncoming;
}

@immutable
class ChatBubbleColors {
  const ChatBubbleColors({
    this.outgoing = ChatBubbleColor.ember,
    this.incoming = ChatBubbleColor.stone,
  });
  final ChatBubbleColor outgoing, incoming;
}

class ChatAppearance extends Notifier<ChatBubbleColors> {
  @override
  ChatBubbleColors build() {
    // A temporary, in-memory choice that belongs to the signed-in ACCOUNT: watching the uid rebuilds
    // (and so resets) it on sign-out or when another account signs in on this phone. A token refresh
    // for the same account keeps the same uid and keeps the choice.
    ref.watch(authUserProvider.select((user) => user.value?.uid));
    return const ChatBubbleColors();
  }

  void outgoing(ChatBubbleColor color) =>
      state = ChatBubbleColors(outgoing: color, incoming: state.incoming);
  void incoming(ChatBubbleColor color) =>
      state = ChatBubbleColors(outgoing: state.outgoing, incoming: color);
  void reset() => state = const ChatBubbleColors();
}

final chatBubbleColorsProvider =
    NotifierProvider<ChatAppearance, ChatBubbleColors>(ChatAppearance.new);
