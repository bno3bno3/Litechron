import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:litechron/worker/fuse.dart';

Map<String, dynamic> versionInfo({bool newer = true}) => {
      'version': Fuse.version.join('.'),
      'build': Fuse.build + (newer ? 1 : 0),
      'beta': false,
      'url': '${Fuse.projectUrl}/releases/latest',
    };

void main() {
  test('manual check takes over startup result without duplicate prompts',
      () async {
    final response = Completer<Map<String, dynamic>>();
    final fuse = Fuse(fetchVersion: () => response.future, save: (_) async {});
    final automatic = fuse.checkUpdate();
    final manual = fuse.checkUpdate(force: true);
    response.complete(versionInfo());
    expect(await automatic, UpdateCheckResult.skipped);
    expect(await manual, UpdateCheckResult.available);
  });

  test('manual check bypasses interval and concurrent checks share one request',
      () async {
    var requests = 0;
    final response = Completer<Map<String, dynamic>>();
    final fuse = Fuse(
        fetchVersion: () {
          requests++;
          return response.future;
        },
        save: (_) async {});
    fuse.lastUpdateTime = DateTime.now();
    expect(await fuse.checkUpdate(), UpdateCheckResult.skipped);
    expect(requests, 0);
    final first = fuse.checkUpdate(force: true);
    final second = fuse.checkUpdate(force: true);
    response.complete(versionInfo());
    expect(await first, UpdateCheckResult.available);
    expect(await second, UpdateCheckResult.available);
    expect(requests, 1);
  });

  test('restart restores update badge and download URL from saved JSON',
      () async {
    Map<String, dynamic>? saved;
    final fuse = Fuse(
      fetchVersion: () async => versionInfo(),
      save: (value) async {
        saved = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
      },
    );
    expect(await fuse.checkUpdate(), UpdateCheckResult.available);
    final restored = Fuse.fromJson(saved!);
    expect(restored.hasNewVersion, isTrue);
    expect(restored.downloadUrl, fuse.downloadUrl);
    expect(await restored.checkUpdate(), UpdateCheckResult.skipped);
  });

  test('old persisted data remains readable and installed update clears badge',
      () {
    final legacy = {'lastUpdateTime': DateTime.now().toIso8601String()};
    expect(Fuse.fromJson(legacy).hasNewVersion, isFalse);
    final installed = Fuse.fromJson({
      ...legacy,
      'remoteVersion': Fuse.version,
      'remoteBuild': Fuse.build,
      'remoteIsBeta': Fuse.isBeta,
    });
    expect(installed.hasNewVersion, isFalse);
  });

  test('older CDN data and network errors preserve known update', () async {
    var response = versionInfo();
    var fail = false;
    final fuse = Fuse(
        fetchVersion: () async {
          if (fail) throw Exception('Network unavailable');
          return response;
        },
        save: (_) async {});
    await fuse.checkUpdate();
    final knownBuild = fuse.remoteBuild;
    response = versionInfo(newer: false)..['url'] = 'https://example.org/old';
    expect(await fuse.checkUpdate(force: true), UpdateCheckResult.available);
    expect(fuse.remoteBuild, knownBuild);
    expect(fuse.downloadUrl, Fuse.releaseUrl);
    final successfulTime = fuse.lastUpdateTime;
    fail = true;
    expect(await fuse.checkUpdate(force: true), UpdateCheckResult.failed);
    expect(fuse.hasNewVersion, isTrue);
    expect(fuse.lastUpdateTime, successfulTime);
  });

  test('invalid response fails without entering the 12 hour wait', () async {
    var response = <String, dynamic>{'version': '1.0', 'build': 3};
    final fuse = Fuse(fetchVersion: () async => response, save: (_) async {});
    final previousTime = fuse.lastUpdateTime;
    expect(await fuse.checkUpdate(), UpdateCheckResult.failed);
    expect(fuse.lastUpdateTime, previousTime);
    expect(fuse.remoteVersion, isNull);
    response = versionInfo(newer: false);
    expect(await fuse.checkUpdate(), UpdateCheckResult.upToDate);
  });

  test('timeout permits retry and late response cannot replace newer state',
      () async {
    final delayed = Completer<Map<String, dynamic>>();
    var calls = 0;
    final fuse = Fuse(
      fetchVersion: () =>
          ++calls == 1 ? delayed.future : Future.value(versionInfo()),
      save: (_) async {},
      timeout: const Duration(milliseconds: 20),
    );
    expect(await fuse.checkUpdate(), UpdateCheckResult.failed);
    expect(await fuse.checkUpdate(), UpdateCheckResult.available);
    delayed.complete(versionInfo(newer: false));
    await Future<void>.delayed(Duration.zero);
    expect(fuse.hasNewVersion, isTrue);
    expect(fuse.remoteBuild, Fuse.build + 1);
  });

  test('persistence failure does not suppress the next attempt', () async {
    final fuse = Fuse(
      fetchVersion: () async => versionInfo(),
      save: (_) async => throw Exception('Storage unavailable'),
    );
    final previousTime = fuse.lastUpdateTime;
    expect(await fuse.checkUpdate(), UpdateCheckResult.failed);
    expect(fuse.lastUpdateTime, previousTime);
    expect(await fuse.checkUpdate(), UpdateCheckResult.failed);
  });
}
