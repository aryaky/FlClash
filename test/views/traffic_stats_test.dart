import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/traffic_stats.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _subscription({
  required int id,
  required int upload,
  required int download,
  required int total,
}) {
  return Profile.normal(label: 'sub', url: 'https://example.com/$id').copyWith(
    id: id,
    subscriptionInfo: SubscriptionInfo(
      upload: upload,
      download: download,
      total: total,
    ),
  );
}

void main() {
  test('only airport subscription profiles contribute traffic', () {
    final items = airportSubscriptionTrafficsOf([
      _subscription(id: 1, upload: 10, download: 20, total: 100),
      _subscription(id: 2, upload: 5, download: 5, total: 0),
      Profile.custom(label: 'local'),
      Profile.normal(label: 'file'),
    ]);

    expect(items.length, 2);
    final summary = subscriptionTrafficSummaryOf(items);
    expect(summary.reported, 2);
    expect(summary.used, 40);
    expect(summary.total, 100);
  });

  test('subscriptions without a report are listed but not summed', () {
    final items = airportSubscriptionTrafficsOf([
      _subscription(id: 1, upload: 0, download: 0, total: 0),
    ]);

    expect(items.length, 1);
    final summary = subscriptionTrafficSummaryOf(items);
    expect(summary.reported, 0);
    expect(summary.used, 0);
    expect(summary.total, 0);
  });
}
