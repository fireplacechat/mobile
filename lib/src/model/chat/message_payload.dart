import 'dart:convert';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/message_quote.dart';

/// The plaintext inside every encrypted envelope: JSON with a version `v`.
///
/// - v1: a text message (`type: text`, `body`).
/// - v2: a reaction or a delete for everyone (the mutation's fields).
/// - v3: an edit, or a text message that quotes another (`quote`).
///
/// Each message also carries the sender's clock time `ts`. Changing these
/// fields changes the wire format, which needs a decision record.
///
/// A text message may carry `color`, the name of the sender's own chat colour
/// (decision 0052), so the other person's phone can show their messages in
/// it. Apps from before it ignore the field.
List<int> encodeMessagePayload({
  required String text,
  required DateTime now,
  MessageQuote? quote,
  MessageMutation? mutation,
  String? color,
}) => utf8.encode(
  jsonEncode({
    'v': quote != null || mutation?.kind == MessageMutationKind.edit
        ? 3
        : mutation == null
        ? 1
        : 2,
    if (mutation == null) ...{
      'type': 'text',
      'body': text,
      if (quote != null) 'quote': quote.toJson(),
      'color': ?color,
    } else
      ...mutation.toJson(),
    'ts': now.millisecondsSinceEpoch,
  }),
);

/// What a received payload says. An unreadable payload is a malformed
/// message; an unknown kind from a newer app shows a placeholder.
typedef DecodedPayload = ({
  String body,
  MessageStatus status,
  MessageMutation? mutation,
  MessageQuote? quote,

  /// The sender's own colour name, when the message carried a well-formed one.
  String? color,
});

DecodedPayload decodeMessagePayload(List<int> plain) {
  try {
    final payload = jsonDecode(utf8.decode(plain));
    if (payload is Map &&
        payload['type'] == 'text' &&
        payload['body'] is String) {
      return (
        body: payload['body'] as String,
        status: MessageStatus.ok,
        mutation: null,
        quote: payload['v'] == 3 && payload['quote'] != null
            ? MessageQuote.fromJson(Map<String, dynamic>.from(payload['quote']))
            : null,
        color: _colorName(payload['color']),
      );
    }
    if (payload is Map &&
        ((payload['v'] == 2 &&
                (payload['type'] == 'reaction' ||
                    payload['type'] == 'delete')) ||
            (payload['v'] == 3 && payload['type'] == 'edit'))) {
      return (
        body: '',
        status: MessageStatus.ok,
        mutation: MessageMutation.fromJson(Map<String, dynamic>.from(payload)),
        quote: null,
        color: null,
      );
    }
    return (
      body: '[unsupported message]',
      status: MessageStatus.ok,
      mutation: null,
      quote: null,
      color: null,
    );
  } catch (_) {
    return (
      body: 'Malformed message.',
      status: MessageStatus.undecryptable,
      mutation: null,
      quote: null,
      color: null,
    );
  }
}

/// A colour name is lower-case letters only; anything else is dropped, never
/// shown or stored.
String? _colorName(Object? value) =>
    value is String && RegExp(r'^[a-z]{1,24}$').hasMatch(value) ? value : null;
