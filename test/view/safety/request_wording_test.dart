import 'package:fireplace/src/view/safety/request_wording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fred = WaitingRequest('fred');
  const anna = WaitingRequest('anna');
  const theo = WaitingRequest('theo');
  const zoe = WaitingRequest('zoe');
  const ida = WaitingRequest('ida');

  test('names who is waiting, by username', () {
    expect(requestSummary(const []), '');
    expect(requestSummary(const [fred]), 'fred wants to chat');
    expect(
      requestSummary(const [WaitingRequest('fred', group: true)]),
      'fred invited you to a group',
    );
    expect(requestSummary(const [fred, anna]), 'fred and anna');
    expect(requestSummary(const [fred, anna, theo]), 'fred, anna and theo');
    expect(
      requestSummary(const [fred, anna, theo, zoe]),
      'fred, anna and 2 others',
    );
    expect(
      requestSummary(const [fred, anna, theo, zoe, ida]),
      'fred, anna and 3 others',
    );
  });

  test('someone with a request and an invitation is named once', () {
    expect(
      requestSummary(const [fred, WaitingRequest('fred', group: true)]),
      'fred is waiting',
    );
    expect(
      requestSummary(const [fred, anna, WaitingRequest('fred', group: true)]),
      'fred and anna',
    );
  });
}
