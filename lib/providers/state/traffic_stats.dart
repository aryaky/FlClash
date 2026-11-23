part of '../state.dart';

@riverpod
Future<List<TrafficDayTotal>> trafficDays(Ref ref) {
  return database.trafficStatsDao.dailyTotals();
}

@riverpod
Future<List<TrafficProfileTotal>> trafficDayProfiles(Ref ref, String statDate) {
  return database.trafficStatsDao.profileTotals(statDate);
}

@Riverpod(keepAlive: true)
Future<DomainGrouper> domainGrouper(Ref ref) => DomainGrouper.load();

typedef TrafficDomainTotal = ({String domain, int up, int down});

/// Exact hosts of one day and profile, bucketed by registrable domain so the
/// sheet can show one row per domain and still drill into the hosts beneath.
@riverpod
Future<Map<String, List<TrafficHostTotal>>> trafficDayDomainHosts(
  Ref ref,
  ({String statDate, int profileId}) key,
) async {
  final hosts = await database.trafficStatsDao.hostTotals(
    key.statDate,
    key.profileId,
  );
  final grouper = await ref.watch(domainGrouperProvider.future);
  final grouped = <String, List<TrafficHostTotal>>{};
  for (final host in hosts) {
    grouped.putIfAbsent(grouper.group(host.destKey), () => []).add(host);
  }
  return grouped;
}
