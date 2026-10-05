import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/fireplace_services.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ActivityService activity;
  final now = DateTime.utc(2026, 10, 4, 12);

  setUp(() async {
    db = FakeFirebaseFirestore();
    activity = ActivityService(db);
    await db.collection('users').doc('alice').set({'username': 'alice'});
  });

  Future<Object?> stamp() async =>
      (await db.collection('users').doc('alice').get()).data()?['lastActiveAt'];

  test('stamps the account when it has never been stamped', () async {
    expect(
      await activity.markActiveIfDue('alice', {'username': 'alice'}, now: now),
      isTrue,
    );
    expect(await stamp(), isNotNull);
  });

  test(
    'does not write again while the stamp is recent (under 13 hours)',
    () async {
      final recent = Timestamp.fromDate(
        now.subtract(const Duration(hours: 12)),
      );
      expect(
        await activity.markActiveIfDue('alice', {
          'lastActiveAt': recent,
        }, now: now),
        isFalse,
      );
      expect(await stamp(), isNull);
    },
  );

  test('refreshes the stamp once it is older than 13 hours', () async {
    final old = Timestamp.fromDate(now.subtract(const Duration(hours: 14)));
    expect(
      await activity.markActiveIfDue('alice', {'lastActiveAt': old}, now: now),
      isTrue,
    );
    expect(await stamp(), isNotNull);
  });

  test('a failed write is swallowed and never throws', () async {
    final ghost = ActivityService(db);
    // No such user document: update() throws not-found; the service must report false instead.
    expect(await ghost.markActiveIfDue('nobody', null, now: now), isFalse);
  });

  test(
    'the refresh interval stays above the 12-hour floor in the security rules',
    () {
      expect(
        ActivityService.refreshAfter,
        greaterThan(const Duration(hours: 12)),
      );
    },
  );
}
