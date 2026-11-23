import 'package:fl_clash/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

TrafficStatRecord _row(
  String date,
  int profileId,
  String destKey,
  int up,
  int down, {
  String profileName = 'Airport',
}) {
  return TrafficStatRecord(
    statDate: date,
    profileId: profileId,
    destKey: destKey,
    profileName: profileName,
    up: up,
    down: down,
  );
}

void main() {
  late Database database;
  late TrafficStatsDao dao;

  setUp(() {
    database = Database(NativeDatabase.memory());
    dao = database.trafficStatsDao;
  });

  tearDown(() async {
    await database.close();
  });

  test('accumulating the same bucket sums the deltas', () async {
    await dao.accumulate([_row('2026-11-22', 1, 'github.com', 100, 40)]);
    await dao.accumulate([
      _row(
        '2026-11-22',
        1,
        'github.com',
        50,
        10,
        profileName: 'Airport Renamed',
      ),
    ]);

    final days = await dao.dailyTotals();
    expect(days, [(statDate: '2026-11-22', up: 150, down: 50)]);
    final profiles = await dao.profileTotals('2026-11-22');
    expect(profiles.single.profileName, 'Airport Renamed');
  });

  test('daily totals group by day, newest first', () async {
    await dao.accumulate([
      _row('2026-11-21', 1, 'a.example', 10, 1),
      _row('2026-11-22', 1, 'a.example', 20, 2),
      _row('2026-11-22', 2, 'b.example', 5, 5),
    ]);

    expect(await dao.dailyTotals(), [
      (statDate: '2026-11-22', up: 25, down: 7),
      (statDate: '2026-11-21', up: 10, down: 1),
    ]);
  });

  test('profile totals rank a day by traffic and host totals follow', () async {
    await dao.accumulate([
      _row('2026-11-22', 1, 'small.example', 10, 0, profileName: 'A'),
      _row('2026-11-22', 1, 'big.example', 300, 100, profileName: 'A'),
      _row('2026-11-22', 2, 'other.example', 40, 40, profileName: 'B'),
    ]);

    expect(await dao.profileTotals('2026-11-22'), [
      (profileId: 1, profileName: 'A', up: 310, down: 100),
      (profileId: 2, profileName: 'B', up: 40, down: 40),
    ]);
    expect(await dao.hostTotals('2026-11-22', 1), [
      (destKey: 'big.example', up: 300, down: 100),
      (destKey: 'small.example', up: 10, down: 0),
    ]);
  });

  test('other days and profiles stay out of a host query', () async {
    await dao.accumulate([
      _row('2026-11-21', 1, 'github.com', 1, 1),
      _row('2026-11-22', 1, 'github.com', 2, 2),
      _row('2026-11-22', 2, 'github.com', 3, 3),
    ]);

    expect(await dao.hostTotals('2026-11-22', 1), [
      (destKey: 'github.com', up: 2, down: 2),
    ]);
  });
}
