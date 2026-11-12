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
List<int> encodeMessagePayload({
  required String text,
  required DateTime now,
  MessageQuote? quote,
  MessageMutation? mutation,
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
      );
    }
    return (
      body: '[unsupported message]',
      status: MessageStatus.ok,
      mutation: null,
      quote: null,
    );
  } catch (_) {
    return (
      body: 'Malformed message.',
      status: MessageStatus.undecryptable,
      mutation: null,
      quote: null,
    );
  }
}
