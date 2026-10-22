import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:litechron/worker/fuse.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> initialize({String version = '2.3.4', String build = '42'}) {
    PackageInfo.setMockInitialValues(
      appName: 'Litechron',
      packageName: 'io.github.bno3bno3.litechron',
      version: version,
      buildNumber: build,
      buildSignature: '',
    );
    return Fuse.initializeVersion();
  }

  test('display and update checks use the installed package version', () async {
    await initialize();
    final fuse = Fuse(
      fetchVersion: () async => {'version': '2.3.4', 'build': 42},
      save: (_) async {},
    );

    expect(Fuse.version, [2, 3, 4]);
    expect(Fuse.build, 42);
    expect(fuse.displayVersion, '2.3.4');
    expect(await fuse.checkUpdate(), UpdateCheckResult.upToDate);
  });

  test('a higher installed build clears a cached update on startup', () async {
    await initialize(build: '43');
    final restored = Fuse.fromJson({
      'lastUpdateTime': DateTime.now().toIso8601String(),
      'remoteVersion': [2, 3, 4],
      'remoteBuild': 43,
      'remoteIsBeta': false,
    });

    expect(restored.hasNewVersion, isFalse);
    expect(Fuse.build, 43);
  });

  test('development suffix is displayed and accepts numeric update versions',
      () async {
    await initialize(version: '2.3.4-dev');
    var remoteBuild = 42;
    final fuse = Fuse(
      fetchVersion: () async => {'version': '2.3.4', 'build': remoteBuild},
      save: (_) async {},
    );

    expect(fuse.displayVersion, '2.3.4-dev');
    expect(await fuse.checkUpdate(), UpdateCheckResult.upToDate);
    remoteBuild++;
    expect(await fuse.checkUpdate(force: true), UpdateCheckResult.available);
  });

  test('changing installed version also changes update comparisons', () async {
    await initialize(version: '3.0.0', build: '1');
    final fuse = Fuse(
      fetchVersion: () async => {'version': '2.9.9', 'build': 999},
      save: (_) async {},
    );

    expect(fuse.displayVersion, '3.0.0');
    expect(await fuse.checkUpdate(), UpdateCheckResult.upToDate);
  });

  test('invalid installed version information is rejected', () async {
    await expectLater(initialize(version: 'invalid'), throwsFormatException);
    await expectLater(initialize(build: 'invalid'), throwsFormatException);
    await expectLater(initialize(build: '-1'), throwsFormatException);
  });
}
