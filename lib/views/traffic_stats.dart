import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/traffic_accounting.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Traffic the airport itself reports for one of its subscriptions.
/// Local files and hand-written configs are deliberately left out.
typedef SubscriptionTraffic = ({Profile profile, SubscriptionInfo info});

List<SubscriptionTraffic> airportSubscriptionTrafficsOf(
  Iterable<Profile> profiles,
) {
  return [
    for (final profile in profiles)
      if (profile.type == ProfileType.url)
        (
          profile: profile,
          info: profile.subscriptionInfo ?? const SubscriptionInfo(),
        ),
  ];
}

({int reported, int used, int total}) subscriptionTrafficSummaryOf(
  Iterable<SubscriptionTraffic> items,
) {
  var reported = 0;
  var used = 0;
  var total = 0;
  for (final item in items) {
    final info = item.info;
    final itemUsed = info.upload + info.download;
    if (itemUsed == 0 && info.total == 0) {
      continue;
    }
    reported++;
    used += itemUsed;
    total += info.total;
  }
  return (reported: reported, used: used, total: total);
}

String trafficUpDownLabel(AppLocalizations appLocalizations, int up, int down) {
  return '${appLocalizations.upload} ${up.traffic.show}  '
      '${appLocalizations.download} ${down.traffic.show}';
}

class TrafficStatsView extends ConsumerStatefulWidget {
  const TrafficStatsView({super.key});

  @override
  ConsumerState<TrafficStatsView> createState() => _TrafficStatsViewState();
}

class _TrafficStatsViewState extends ConsumerState<TrafficStatsView> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(trafficAccountingFlushInterval, (_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(trafficDaysProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _showDayDetail(String statDate) {
    showNestedSheet<void>(
      context,
      builder: (_) => _TrafficDaySheet(statDate: statDate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final days = ref.watch(trafficDaysProvider).value ?? const [];
    final items = airportSubscriptionTrafficsOf(ref.watch(profilesProvider));
    final summary = subscriptionTrafficSummaryOf(items);
    return Scaffold(
      title: appLocalizations.trafficUsage,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
              top: context.sectionsTopPadding,
              bottom: 16 + context.bottomInset,
            ),
            sliver: SliverMainAxisGroup(
              slivers: [
                if (days.isEmpty)
                  SliverToBoxAdapter(
                    child: NullStatus(
                      label: appLocalizations.nullTip(
                        appLocalizations.measuredTraffic,
                      ),
                      illustration: NullStatusIllustration.data,
                    ),
                  )
                else
                  generateSliverSection(
                    title: appLocalizations.measuredTraffic,
                    items: days,
                    itemBuilder: (day) => DecorationListItem(
                      onPressed: () => _showDayDetail(day.statDate),
                      title: Text(day.statDate),
                      subtitle: Text(
                        trafficUpDownLabel(appLocalizations, day.up, day.down),
                      ),
                      trailing: Text((day.up + day.down).traffic.show),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: Text(
                      appLocalizations.measuredTrafficNote,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _TrafficSummary(summary: summary)),
                generateSliverSection(
                  title: appLocalizations.subscriptionInfo,
                  items: items,
                  itemBuilder: (item) => _SubscriptionTrafficItem(
                    item,
                    key: ValueKey(item.profile.id),
                    onTap: () => _showQuotaDetail(context, item),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQuotaDetail(BuildContext context, SubscriptionTraffic item) {
    showNestedSheet<void>(
      context,
      builder: (_) => Scaffold(
        title: item.profile.realLabel,
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
                top: context.contentTopPadding,
                bottom: 20 + context.bottomInset,
              ),
              sliver: SliverToBoxAdapter(
                child: _TrafficDetail(info: item.info),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficDaySheet extends ConsumerWidget {
  final String statDate;

  const _TrafficDaySheet({required this.statDate});

  void _showDomains(BuildContext context, TrafficProfileTotal profile) {
    showNestedSheet<void>(
      context,
      builder: (_) => _TrafficDomainSheet(
        statDate: statDate,
        profileId: profile.profileId,
        profileName: profile.profileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final profiles =
        ref.watch(trafficDayProfilesProvider(statDate)).value ?? const [];
    return Scaffold(
      title: statDate,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
              top: context.contentTopPadding,
              bottom: 20 + context.bottomInset,
            ),
            sliver: generateSliverSection(
              title: appLocalizations.subscriptionInfo,
              items: profiles,
              itemBuilder: (profile) => DecorationListItem(
                onPressed: () => _showDomains(context, profile),
                title: Text(
                  profile.profileName.isEmpty
                      ? appLocalizations.unknown
                      : profile.profileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  trafficUpDownLabel(
                    appLocalizations,
                    profile.up,
                    profile.down,
                  ),
                ),
                trailing: Text((profile.up + profile.down).traffic.show),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficDomainSheet extends ConsumerWidget {
  final String statDate;
  final int profileId;
  final String profileName;

  const _TrafficDomainSheet({
    required this.statDate,
    required this.profileId,
    required this.profileName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final grouped =
        ref
            .watch(
              trafficDayDomainHostsProvider((
                statDate: statDate,
                profileId: profileId,
              )),
            )
            .value ??
        const <String, List<TrafficHostTotal>>{};
    final domains = [
      for (final MapEntry(key: domain, value: hosts) in grouped.entries)
        (
          domain: domain,
          up: hosts.fold(0, (sum, host) => sum + host.up),
          down: hosts.fold(0, (sum, host) => sum + host.down),
        ),
    ]..sort((a, b) => (b.up + b.down).compareTo(a.up + a.down));
    return Scaffold(
      title: profileName.isEmpty ? statDate : profileName,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
              top: context.contentTopPadding,
              bottom: 20 + context.bottomInset,
            ),
            sliver: generateSliverSection(
              title: appLocalizations.destinations,
              items: domains,
              itemBuilder: (domain) => DecorationListItem(
                onPressed: () => showNestedSheet<void>(
                  context,
                  builder: (_) => _TrafficHostSheet(
                    domain: domain.domain,
                    hosts: grouped[domain.domain] ?? const [],
                  ),
                ),
                title: Text(
                  domain.domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  trafficUpDownLabel(appLocalizations, domain.up, domain.down),
                ),
                trailing: Text((domain.up + domain.down).traffic.show),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficHostSheet extends StatelessWidget {
  final String domain;
  final List<TrafficHostTotal> hosts;

  const _TrafficHostSheet({required this.domain, required this.hosts});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Scaffold(
      title: appLocalizations.details(domain),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
              top: context.contentTopPadding,
              bottom: 20 + context.bottomInset,
            ),
            sliver: generateSliverSection(
              items: hosts,
              itemBuilder: (host) => DecorationListItem(
                title: Text(
                  host.destKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  trafficUpDownLabel(appLocalizations, host.up, host.down),
                ),
                trailing: Text((host.up + host.down).traffic.show),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficSummary extends StatelessWidget {
  final ({int reported, int used, int total}) summary;

  const _TrafficSummary({required this.summary});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: generateSection(
        items: [
          DecorationListItem(
            title: Text(appLocalizations.usedTraffic),
            subtitle: Text(summary.used.traffic.show),
          ),
          DecorationListItem(
            title: Text(appLocalizations.totalTraffic),
            subtitle: Text(
              summary.total > 0
                  ? summary.total.traffic.show
                  : appLocalizations.unknown,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionTrafficItem extends StatelessWidget {
  final SubscriptionTraffic item;
  final VoidCallback onTap;

  const _SubscriptionTrafficItem(this.item, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = item.info;
    final used = info.upload + info.download;
    final hasReport = used > 0 || info.total > 0;
    final progress = info.total > 0
        ? (used / info.total).clamp(0.0, 1.0).toDouble()
        : null;
    return DecorationListItem(
      onPressed: onTap,
      title: Text(
        item.profile.realLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: hasReport
          ? Text('${used.traffic.show} / ${info.total.traffic.show}')
          : Text(context.appLocalizations.unknown),
      trailing: progress == null
          ? null
          : SizedBox(
              width: 72,
              child: LinearProgressIndicator(
                minHeight: 4,
                value: progress,
                backgroundColor: context.colorScheme.primary.opacity15,
              ),
            ),
    );
  }
}

class _TrafficDetail extends StatelessWidget {
  final SubscriptionInfo info;

  const _TrafficDetail({required this.info});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final used = info.upload + info.download;
    final expire = info.expireDate?.show ?? appLocalizations.infiniteTime;
    return SelectionArea(
      child: generateSection(
        title: appLocalizations.details(appLocalizations.trafficUsage),
        items: [
          DecorationListItem(
            title: Text(appLocalizations.upload),
            subtitle: Text(info.upload.traffic.show),
          ),
          DecorationListItem(
            title: Text(appLocalizations.download),
            subtitle: Text(info.download.traffic.show),
          ),
          DecorationListItem(
            title: Text(appLocalizations.usedTraffic),
            subtitle: Text(used.traffic.show),
          ),
          DecorationListItem(
            title: Text(appLocalizations.totalTraffic),
            subtitle: Text(
              info.total > 0
                  ? info.total.traffic.show
                  : appLocalizations.unknown,
            ),
          ),
          DecorationListItem(
            title: Text(appLocalizations.expireTime),
            subtitle: Text(expire),
          ),
        ],
      ),
    );
  }
}
