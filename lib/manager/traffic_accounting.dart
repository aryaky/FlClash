import 'dart:async';

import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';

typedef TrafficProfileLookup = ({int id, String name})? Function();

typedef TrafficSink = Future<void> Function(List<TrafficStatRecord> deltas);

typedef TrafficClock = DateTime Function();

const Duration beijingOffset = Duration(hours: 8);

const Duration trafficAccountingFlushInterval = Duration(seconds: 15);

const String unknownDestKey = 'unknown';

class _TrackedConnection {
  _TrackedConnection({
    required this.profileId,
    required this.profileName,
    required this.destKey,
    required this.up,
    required this.down,
  });

  final int profileId;
  final String profileName;
  final String destKey;
  int up;
  int down;
}

class _BucketKey {
  const _BucketKey(this.date, this.profileId, this.destKey);

  final String date;
  final int profileId;
  final String destKey;

  @override
  bool operator ==(Object other) {
    return other is _BucketKey &&
        other.date == date &&
        other.profileId == profileId &&
        other.destKey == destKey;
  }

  @override
  int get hashCode => Object.hash(date, profileId, destKey);
}

/// Accumulates the Core's per-connection byte counters into
/// (Beijing day, profile, destination) buckets and hands whole buckets to the
/// sink on [flush]. Deltas are attributed to the profile that was active when
/// the connection opened; the destination is the SNI/HTTP host, falling back
/// to the destination IP, then the remote destination.
class TrafficAccountant {
  TrafficAccountant({
    required this.lookupProfile,
    required this.sink,
    this.now = DateTime.now,
  });

  final TrafficProfileLookup lookupProfile;
  final TrafficSink sink;
  final TrafficClock now;

  final Map<String, _TrackedConnection> _connections = {};
  final Map<_BucketKey, ({int up, int down, String profileName})> _pending = {};

  static final RegExp _portSuffix = RegExp(r':\d+$');

  static String destKeyOf(Metadata metadata) {
    final host = metadata.host.toLowerCase().replaceFirst(_portSuffix, '');
    if (host.isNotEmpty) {
      return host;
    }
    final ip = metadata.destinationIP.trim();
    if (ip.isNotEmpty) {
      return ip;
    }
    final remote = metadata.remoteDestination.trim().replaceFirst(
      _portSuffix,
      '',
    );
    return remote.isNotEmpty ? remote : unknownDestKey;
  }

  static String beijingDate(DateTime time) {
    final beijing = time.toUtc().add(beijingOffset);
    final y = beijing.year.toString().padLeft(4, '0');
    final m = beijing.month.toString().padLeft(2, '0');
    final d = beijing.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void observeOpen(TrackerInfo info) {
    if (_connections.containsKey(info.id)) {
      return;
    }
    final profile = lookupProfile();
    if (profile == null) {
      return;
    }
    _connections[info.id] = _TrackedConnection(
      profileId: profile.id,
      profileName: profile.name,
      destKey: destKeyOf(info.metadata),
      up: info.upload,
      down: info.download,
    );
  }

  void observeTraffic(Map<String, RequestTraffic> traffic) {
    for (final MapEntry(key: id, value: counters) in traffic.entries) {
      final connection = _connections[id];
      if (connection == null) {
        continue;
      }
      final up = counters.upload - connection.up;
      final down = counters.download - connection.down;
      connection.up = counters.upload;
      connection.down = counters.download;
      if (up <= 0 && down <= 0) {
        continue;
      }
      final key = _BucketKey(
        beijingDate(now()),
        connection.profileId,
        connection.destKey,
      );
      final bucket = _pending[key] ?? (up: 0, down: 0, profileName: '');
      _pending[key] = (
        up: bucket.up + (up > 0 ? up : 0),
        down: bucket.down + (down > 0 ? down : 0),
        profileName: connection.profileName,
      );
    }
  }

  void pruneClosed(Set<String> liveIds) {
    _connections.removeWhere((id, _) => !liveIds.contains(id));
  }

  Future<void> flush() async {
    if (_pending.isEmpty) {
      return;
    }
    final drained = Map.of(_pending);
    _pending.clear();
    try {
      await sink([
        for (final MapEntry(key: key, value: amount) in drained.entries)
          TrafficStatRecord(
            statDate: key.date,
            profileId: key.profileId,
            destKey: key.destKey,
            profileName: amount.profileName,
            up: amount.up,
            down: amount.down,
          ),
      ]);
    } catch (_) {
      // A failed write must not cost the increments; merge them back under
      // anything observed meanwhile and retry on the next flush.
      for (final MapEntry(key: key, value: amount) in drained.entries) {
        final current = _pending[key] ?? (up: 0, down: 0, profileName: '');
        _pending[key] = (
          up: current.up + amount.up,
          down: current.down + amount.down,
          profileName: amount.profileName,
        );
      }
      rethrow;
    }
  }
}
