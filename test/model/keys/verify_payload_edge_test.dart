import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const digits = '012340123401234012340123401234012340123401234012340123401234';

  test('payload round trips the formatted safety number', () {
    final formatted = List.generate(
      12,
      (i) => digits.substring(i * 5, i * 5 + 5),
    ).join(' ');
    final payload = VerifyPayload.fromSafetyNumber(formatted);

    expect(payload.digits, digits);
    expect(VerifyPayload.parse(payload.encode())?.digits, digits);
    expect(payload.matches(formatted), isTrue);
  });

  test('parser rejects malformed, wrong-version and non-60-digit payloads', () {
    expect(VerifyPayload.parse(null), isNull);
    expect(VerifyPayload.parse('fireplace://verify/2/$digits'), isNull);
    expect(VerifyPayload.parse('fireplace://verify/1/${digits}0'), isNull);
    expect(
      VerifyPayload.parse('fireplace://verify/1/${digits.substring(1)}'),
      isNull,
    );
    expect(
      VerifyPayload.parse(
        'fireplace://verify/1/${digits.replaceFirst('0', 'x')}',
      ),
      isNull,
    );
    expect(VerifyPayload.parse('https://fireplace/verify/1/$digits'), isNull);
  });
}
