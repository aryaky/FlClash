import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/manager/traffic_accounting.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInfo _conn(
  String id, {
  String host = '',
  String ip = '',
  String remote = '',
  int upload = 0,
  int download = 0,
}) {
  return TrackerInfo(
    id: id,
    upload: upload,
    download: download,
    start: DateTime(2026, 11, 22),
    metadata: Metadata(
      host: host,
      destinationIP: ip,
      remoteDestination: remote,
    ),
    chains: const ['HK 01'],
    rule: 'MATCH',
    rulePayload: '',
  );
}

void main() {
  group('destKeyOf', () {
    test('prefers the SNI or HTTP host, lowercased and without a port', () {
      expect(
        TrafficAccountant.destKeyOf(
          const Metadata(host: 'WWW.YouTube.COM:443'),
        ),
        'www.youtube.com',
      );
    });

    test('falls back to the destination IP when no host is present', () {
      expect(
        TrafficAccountant.destKeyOf(
          const Metadata(destinationIP: '142.250.4.5'),
        ),
        '142.250.4.5',
      );
    });

    test('falls back to the remote destination last', () {
      expect(
        TrafficAccountant.destKeyOf(
          const Metadata(remoteDestination: '142.250.4.5:8888'),
        ),
        '142.250.4.5',
      );
    });

    test('labels fully anonymous connections unknown', () {
      expect(TrafficAccountant.destKeyOf(const Metadata()), unknownDestKey);
    });
  });

  group('beijingDate', () {
    test('the day flips at 16:00 UTC', () {
      expect(
        TrafficAccountant.beijingDate(DateTime.utc(2026, 11, 22, 15, 59)),
        '2026-11-22',
      );
      expect(
        TrafficAccountant.beijingDate(DateTime.utc(2026, 11, 22, 16, 0)),
        '2026-11-23',
      );
    });
  });

  group('TrafficAccountant', () {
    late List<TrafficStatRecord> flushed;
    late DateTime now;

    TrafficAccountant accountant({({int id, String name})? profile}) {
      return TrafficAccountant(
        lookupProfile: () => profile,
        sink: (records) async => flushed.addAll(records),
        now: () => now,
      );
    }

    setUp(() {
      flushed = [];
      now = DateTime.utc(2026, 11, 22, 16, 30);
    });

    test('deltas since the open baseline land in the day bucket', () async {
      final subject = accountant(profile: (id: 7, name: 'Airport A'));
      subject.observeOpen(
        _conn('a', host: 'github.com', upload: 30, download: 40),
      );
      subject.observeTraffic({'a': (upload: 100, download: 40)});
      await subject.flush();

      expect(flushed, [
        isA<TrafficStatRecord>()
            .having((r) => r.statDate, 'statDate', '2026-11-23')
            .having((r) => r.profileId, 'profileId', 7)
            .having((r) => r.profileName, 'profileName', 'Airport A')
            .having((r) => r.destKey, 'destKey', 'github.com')
            .having((r) => r.up, 'up', 70)
            .having((r) => r.down, 'down', 0),
      ]);
    });

    test(
      'connections opened before the listener are skipped, not counted from zero',
      () async {
        final subject = accountant(profile: (id: 7, name: 'Airport A'));
        subject.observeTraffic({'old': (upload: 500, download: 500)});
        subject.observeTraffic({'old': (upload: 600, download: 500)});
        await subject.flush();
        expect(flushed, isEmpty);
      },
    );

    test('connections opened without an active profile are skipped', () async {
      final subject = accountant(profile: null);
      subject.observeOpen(_conn('a', host: 'github.com'));
      subject.observeTraffic({'a': (upload: 10, download: 10)});
      await subject.flush();
      expect(flushed, isEmpty);
    });

    test('a counter reset re-baselines instead of subtracting', () async {
      final subject = accountant(profile: (id: 7, name: 'Airport A'));
      subject.observeOpen(_conn('a', host: 'github.com'));
      subject.observeTraffic({'a': (upload: 100, download: 0)});
      subject.observeTraffic({'a': (upload: 10, download: 0)});
      subject.observeTraffic({'a': (upload: 30, download: 0)});
      await subject.flush();
      expect(flushed.single.up, 120);
    });

    test('pruning a closed connection stops its accounting', () async {
      final subject = accountant(profile: (id: 7, name: 'Airport A'));
      subject.observeOpen(_conn('a', host: 'github.com'));
      subject.observeTraffic({'a': (upload: 100, download: 0)});
      subject.pruneClosed({});
      subject.observeTraffic({'a': (upload: 400, download: 0)});
      await subject.flush();
      expect(flushed.single.up, 100);
    });

    test(
      'traffic crossing the Beijing midnight splits into two days',
      () async {
        final subject = accountant(profile: (id: 7, name: 'Airport A'));
        now = DateTime.utc(2026, 11, 22, 15, 59);
        subject.observeOpen(_conn('a', host: 'github.com'));
        subject.observeTraffic({'a': (upload: 100, download: 0)});
        now = DateTime.utc(2026, 11, 22, 16, 1);
        subject.observeTraffic({'a': (upload: 250, download: 0)});
        await subject.flush();

        final byDate = {for (final r in flushed) r.statDate: r.up};
        expect(byDate, {'2026-11-22': 100, '2026-11-23': 150});
      },
    );

    test('buckets accumulate across reports before one flush', () async {
      final subject = accountant(profile: (id: 7, name: 'Airport A'));
      subject.observeOpen(_conn('a', host: 'github.com'));
      subject.observeOpen(_conn('b', host: 'github.com'));
      subject.observeTraffic({'a': (upload: 100, download: 0)});
      subject.observeTraffic({'b': (upload: 50, download: 25)});
      await subject.flush();
      expect(flushed.length, 1);
      expect(flushed.single.up, 150);
      expect(flushed.single.down, 25);
    });

    test('a failed write keeps the increments for the next flush', () async {
      var writable = false;
      final subject = TrafficAccountant(
        lookupProfile: () => (id: 7, name: 'Airport A'),
        sink: (records) async {
          if (!writable) {
            throw StateError('database locked');
          }
          flushed.addAll(records);
        },
        now: () => now,
      );
      subject.observeOpen(_conn('a', host: 'github.com'));
      subject.observeTraffic({'a': (upload: 100, download: 0)});
      await expectLater(subject.flush(), throwsStateError);
      subject.observeTraffic({'a': (upload: 180, download: 0)});
      writable = true;
      await subject.flush();

      expect(flushed.length, 1);
      expect(flushed.single.up, 180);
    });
  });
}
