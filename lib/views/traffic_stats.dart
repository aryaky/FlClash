import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
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

class TrafficStatsView extends ConsumerWidget {
  const TrafficStatsView({super.key});

  void _showDetail(BuildContext context, SubscriptionTraffic item) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final items = airportSubscriptionTrafficsOf(ref.watch(profilesProvider));
    final summary = subscriptionTrafficSummaryOf(items);
    return Scaffold(
      title: appLocalizations.trafficUsage,
      body: NullStatusSwitcher(
        isEmpty: items.isEmpty,
        nullStatus: NullStatus(
          label: appLocalizations.nullTip(appLocalizations.trafficUsage),
          illustration: NullStatusIllustration.data,
        ),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
                top: context.sectionsTopPadding,
                bottom: 16 + context.bottomInset,
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: _TrafficSummary(summary: summary),
                  ),
                  generateSliverSection(
                    title: appLocalizations.subscriptionInfo,
                    items: items,
                    itemBuilder: (item) => _SubscriptionTrafficItem(
                      item,
                      key: ValueKey(item.profile.id),
                      onTap: () => _showDetail(context, item),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
