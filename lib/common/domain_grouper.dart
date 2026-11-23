import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:public_suffix/public_suffix.dart';

const publicSuffixListAsset = 'assets/data/public_suffix_list.dat';

/// Groups destination hosts by registrable domain (eTLD+1) off the bundled
/// Public Suffix List snapshot. IPs and anything the list cannot parse stay
/// under their own key, so reconciliation keeps per-IP rows.
class DomainGrouper {
  DomainGrouper(this._rules);

  final SuffixRules _rules;

  static Future<DomainGrouper> load() async {
    final rules = SuffixRules.fromString(
      await rootBundle.loadString(publicSuffixListAsset),
    );
    return DomainGrouper(rules);
  }

  String group(String destKey) {
    if (InternetAddress.tryParse(destKey) != null) {
      return destKey;
    }
    final uri = Uri(scheme: 'http', host: destKey);
    final parsed = PublicSuffix.fromUrl(
      uri,
      suffixRules: _rules,
      leniency: Leniency.allowAll,
    );
    return parsed?.domain ?? destKey;
  }
}
