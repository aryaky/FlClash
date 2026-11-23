import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('LinuxProtocolRegistrationPlan', () {
    const plan = LinuxProtocolRegistrationPlan(
      schemes: protocolSchemes,
      executable: '/home/me/Apps/FlClash.AppImage',
      applicationsDir: '/home/me/.local/share/applications',
    );

    test('writes a hidden desktop entry claiming every scheme', () {
      expect(
        plan.desktopPath,
        '/home/me/.local/share/applications/flclashtest-url-handler.desktop',
      );
      expect(
        plan.desktopEntry,
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=$appName\n'
        'NoDisplay=true\n'
        'Exec="/home/me/Apps/FlClash.AppImage" %u\n'
        'MimeType=x-scheme-handler/clashtest;'
        'x-scheme-handler/clashmetatest;x-scheme-handler/flclashtest;\n',
      );
    });

    test('makes the entry the default handler for every scheme', () {
      expect(plan.xdgMimeArguments, [
        'default',
        'flclashtest-url-handler.desktop',
        'x-scheme-handler/clashtest',
        'x-scheme-handler/clashmetatest',
        'x-scheme-handler/flclashtest',
      ]);
    });

    test('escapes reserved characters in the executable path', () {
      const plan = LinuxProtocolRegistrationPlan(
        schemes: ['flclashtest'],
        executable: r'/opt/my "apps"/$HOME/100%/Fl`Clash\bin',
        applicationsDir: '/tmp',
      );

      expect(plan.exec, r'"/opt/my \"apps\"/\$HOME/100%%/Fl\`Clash\\bin" %u');
    });
  });
}
