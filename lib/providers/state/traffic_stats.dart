part of '../state.dart';

@riverpod
Future<List<TrafficDayTotal>> trafficDays(Ref ref) {
  return database.trafficStatsDao.dailyTotals();
}

@riverpod
Future<List<TrafficProfileTotal>> trafficDayProfiles(Ref ref, String statDate) {
  return database.trafficStatsDao.profileTotals(statDate);
}

@riverpod
Future<List<TrafficHostTotal>> trafficDayHosts(
  Ref ref,
  ({String statDate, int profileId}) key,
) {
  return database.trafficStatsDao.hostTotals(key.statDate, key.profileId);
}
