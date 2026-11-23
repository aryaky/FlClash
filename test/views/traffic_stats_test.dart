import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/traffic_stats.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

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

  testWidgets('measured days render above the quota section', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          () => TestProfiles([
            _subscription(id: 1, upload: 10, download: 20, total: 100),
          ]),
        ),
        trafficDaysProvider.overrideWith(
          (_) async => [(statDate: '2026-11-22', up: 1 << 20, down: 2 << 20)],
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: TrafficStatsView()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Measured traffic'), findsOneWidget);
    expect(find.text('2026-11-22'), findsOneWidget);
    expect(find.text('Subscription info'), findsOneWidget);
    expect(find.text('sub'), findsOneWidget);
  });
}
