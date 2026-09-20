import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:celechron/worker/fuse.dart';

/// Fuse 里硬编码的版本号必须与 pubspec.yaml 一致，否则更新检查会误判。
void main() {
  test('Fuse.version and Fuse.build match pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$', multiLine: true)
            .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 缺少 version: x.y.z+n');

    final pubspecVersion = [1, 2, 3].map((i) => int.parse(match!.group(i)!));
    final pubspecBuild = int.parse(match!.group(4)!);

    expect(Fuse.version, equals(pubspecVersion.toList()));
    expect(Fuse.build, equals(pubspecBuild));
  });
}
