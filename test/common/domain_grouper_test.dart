import 'package:flutter_test/flutter_test.dart';
import 'package:public_suffix/public_suffix.dart';

import 'package:fl_clash/common/domain_grouper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DomainGrouper grouperFrom(List<String> rules) =>
      DomainGrouper(SuffixRules.fromString(rules.join('\n')));

  group('DomainGrouper.group', () {
    final subject = grouperFrom([
      'com',
      'io',
      'cn',
      '*.cn',
      'co.uk',
      '// ===BEGIN PRIVATE DOMAINS===',
      'github.io',
    ]);

    test('collapses hosts to their registrable domain', () {
      expect(subject.group('www.youtube.com'), 'youtube.com');
      expect(subject.group('s.ytimg.com'), 'ytimg.com');
      expect(subject.group('www.googlevideo.com'), 'googlevideo.com');
      expect(subject.group('sub.site.co.uk'), 'site.co.uk');
      expect(subject.group('foo.bar.cn'), 'foo.bar.cn');
    });

    test('private-suffix hosts keep each hosted site as its own group', () {
      expect(subject.group('user.github.io'), 'user.github.io');
      expect(subject.group('deep.sub.user.github.io'), 'user.github.io');
    });

    test('the registrable domain itself is its own group', () {
      expect(subject.group('youtube.com'), 'youtube.com');
    });

    test('IP fallbacks and unparseable keys stay per-key', () {
      expect(subject.group('142.250.4.5'), '142.250.4.5');
      expect(subject.group('fe80::1'), 'fe80::1');
      expect(subject.group('unknown'), 'unknown');
    });

    test('a host that is itself a public suffix has no group of its own', () {
      expect(subject.group('co.uk'), 'co.uk');
    });
  });

  test('the bundled public suffix list asset loads and parses', () async {
    final subject = await DomainGrouper.load();
    expect(subject.group('www.youtube.com'), 'youtube.com');
    expect(subject.group('s.ytimg.com'), 'ytimg.com');
    expect(subject.group('user.github.io'), 'user.github.io');
    expect(subject.group('sub.site.co.uk'), 'site.co.uk');
    expect(subject.group('142.250.4.5'), '142.250.4.5');
  });
}
