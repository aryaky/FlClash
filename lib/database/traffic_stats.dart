part of 'database.dart';

/// Measured traffic accumulated per Beijing-time day, per profile that was
/// active when the connection opened, and per destination host (or IP when
/// the connection carries no SNI/HTTP host).
@DataClassName('TrafficStatRecord')
class TrafficStats extends Table {
  @override
  String get tableName => 'traffic_stats';

  TextColumn get statDate => text()();

  IntColumn get profileId => integer()();

  TextColumn get destKey => text()();

  TextColumn get profileName => text().withDefault(const Constant(''))();

  IntColumn get up => integer().withDefault(const Constant(0))();

  IntColumn get down => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {statDate, profileId, destKey};
}

typedef TrafficDayTotal = ({String statDate, int up, int down});

typedef TrafficProfileTotal = ({
  int profileId,
  String profileName,
  int up,
  int down,
});

typedef TrafficHostTotal = ({String destKey, int up, int down});

@DriftAccessor(tables: [TrafficStats])
class TrafficStatsDao extends DatabaseAccessor<Database>
    with _$TrafficStatsDaoMixin {
  TrafficStatsDao(super.attachedDatabase);

  Future<void> accumulate(Iterable<TrafficStatRecord> deltas) {
    return transaction(() async {
      for (final delta in deltas) {
        final existing =
            await (select(trafficStats)..where(
                  (t) =>
                      t.statDate.equals(delta.statDate) &
                      t.profileId.equals(delta.profileId) &
                      t.destKey.equals(delta.destKey),
                ))
                .getSingleOrNull();
        final record = TrafficStatRecord(
          statDate: delta.statDate,
          profileId: delta.profileId,
          destKey: delta.destKey,
          profileName: delta.profileName,
          up: (existing?.up ?? 0) + delta.up,
          down: (existing?.down ?? 0) + delta.down,
        );
        if (existing == null) {
          await into(trafficStats).insert(record);
        } else {
          await update(trafficStats).replace(record);
        }
      }
    });
  }

  Future<List<TrafficDayTotal>> dailyTotals() async {
    final up = trafficStats.up.sum();
    final down = trafficStats.down.sum();
    final rows =
        await (selectOnly(trafficStats)
              ..addColumns([trafficStats.statDate, up, down])
              ..groupBy([trafficStats.statDate])
              ..orderBy([OrderingTerm.desc(trafficStats.statDate)]))
            .get();
    return [
      for (final row in rows)
        (
          statDate: row.read(trafficStats.statDate)!,
          up: row.read(up) ?? 0,
          down: row.read(down) ?? 0,
        ),
    ];
  }

  Future<List<TrafficProfileTotal>> profileTotals(String statDate) async {
    final up = trafficStats.up.sum();
    final down = trafficStats.down.sum();
    final rows =
        await (selectOnly(trafficStats)
              ..addColumns([
                trafficStats.profileId,
                trafficStats.profileName,
                up,
                down,
              ])
              ..where(trafficStats.statDate.equals(statDate))
              ..groupBy([trafficStats.profileId, trafficStats.profileName])
              ..orderBy([OrderingTerm.desc(up + down)]))
            .get();
    return [
      for (final row in rows)
        (
          profileId: row.read(trafficStats.profileId)!,
          profileName: row.read(trafficStats.profileName)!,
          up: row.read(up) ?? 0,
          down: row.read(down) ?? 0,
        ),
    ];
  }

  Future<List<TrafficHostTotal>> hostTotals(
    String statDate,
    int profileId,
  ) async {
    final up = trafficStats.up.sum();
    final down = trafficStats.down.sum();
    final rows =
        await (selectOnly(trafficStats)
              ..addColumns([trafficStats.destKey, up, down])
              ..where(
                trafficStats.statDate.equals(statDate) &
                    trafficStats.profileId.equals(profileId),
              )
              ..groupBy([trafficStats.destKey])
              ..orderBy([OrderingTerm.desc(up + down)]))
            .get();
    return [
      for (final row in rows)
        (
          destKey: row.read(trafficStats.destKey)!,
          up: row.read(up) ?? 0,
          down: row.read(down) ?? 0,
        ),
    ];
  }
}
