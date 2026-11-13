import 'dart:convert';
import 'dart:io';

import 'package:fireplace/src/model/notifications/notification_preview.dart';
import 'package:fireplace/src/model/chat/message_payload.dart';

Map<String, Object> previewVectors() {
  final bodies = [
    '',
    '   ',
    ' fictional message ',
    '😀' * 1001,
    'e\u0301' * 501,
    '${'a' * 999} \nlast',
    '中文' * 501,
    for (final code in [
      9,
      13,
      32,
      133,
      160,
      5760,
      8192,
      8202,
      8232,
      8239,
      8287,
      12288,
      65279,
      6158,
    ])
      '${String.fromCharCode(code)}fictional${String.fromCharCode(code)}',
  ];
  final targets = [
    '',
    ' \n\t ',
    'fictional short message',
    'a fictional sentence with a nearby word boundary after forty characters',
    '😀' * 41,
    'e\u0301' * 22,
    '${'😀' * 12} ${'a' * 36}',
    for (final code in [9, 133, 160, 8232, 65279])
      'one${String.fromCharCode(code)}two',
  ];
  final payloads = <List<int>>[
    for (final value in [
      {'v': 1, 'type': 'text', 'body': 'fictional text'},
      {'v': 44, 'type': 'text', 'body': 'fictional future text'},
      {
        'v': 3,
        'type': 'text',
        'body': 'fictional quote',
        'quote': {
          'targetId': 'target',
          'senderUid': 'alice',
          'body': 'fictional origin',
        },
      },
      {'v': 3, 'type': 'text', 'body': 'fictional quote', 'quote': 'invalid'},
      for (final operation in ['set', 'clear', 'invalid'])
        {
          'v': 2,
          'type': 'reaction',
          'targetId': 'target',
          'emoji': '❤️',
          'operation': operation,
          'revision': 1,
        },
      for (final revision in [0, 1.0, true, 9007199254740992])
        {
          'v': 2,
          'type': 'reaction',
          'targetId': 'target',
          'emoji': '❤️',
          'operation': 'set',
          'revision': revision,
        },
      for (final emoji in ['hi', '😀', '👩🏽‍💻', '🇬🇧', '1️⃣', '❤️\n'])
        {
          'v': 2,
          'type': 'reaction',
          'targetId': 'target',
          'emoji': emoji,
          'operation': 'set',
          'revision': 1,
        },
      for (final revision in [0, 1, 10, 11])
        {
          'v': 3,
          'type': 'edit',
          'targetId': 'target',
          'body': 'fictional edit',
          'revision': revision,
        },
      {
        'v': 3,
        'type': 'edit',
        'targetId': 'target',
        'body': ' \n ',
        'revision': 1,
      },
      {'v': 2, 'type': 'delete', 'targetId': 'target'},
      {'v': 2, 'type': 'delete', 'targetId': '../invalid'},
      {'v': 8, 'type': 'future'},
      'fictional non-object',
    ])
      utf8.encode(jsonEncode(value)),
    [255],
    utf8.encode('{invalid'),
  ];
  return {
    'bodies': [
      for (final text in bodies)
        {'text': text, 'expected': notificationBody(text)},
    ],
    'reactions': [
      for (final text in targets)
        {
          'text': text,
          'emoji': '❤️',
          'expected': reactionNotificationBody('❤️', text),
        },
    ],
    'payloads': [
      for (final plain in payloads)
        {
          'base64': base64Encode(plain),
          'expected': () {
            final decoded = decodeMessagePayload(plain);
            if (decoded.status.name != 'ok') return null;
            final mutation = decoded.mutation;
            if (mutation == null) return {'kind': 'text', 'body': decoded.body};
            return {
              'kind': mutation.kind.name,
              'target': mutation.targetId,
              if (mutation.kind.name == 'reaction') ...{
                'emoji': mutation.emoji,
                'clear': mutation.operation.name == 'clear',
              },
              if (mutation.kind.name == 'edit') 'body': mutation.body,
            };
          }(),
        },
    ],
  };
}

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Expected an output path.');
  final output = File(args.single);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(previewVectors())}\n',
  );
}
