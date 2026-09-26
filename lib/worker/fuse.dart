import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';

import 'package:litechron/database/database_helper.dart';

enum UpdateCheckResult { available, upToDate, skipped, failed }

class Fuse {
  late DateTime lastUpdateTime;

  /// 与 pubspec.yaml 的 version 保持一致，由 test/fuse_version_test.dart 校验
  static const bool isBeta = false;
  static const version = [1, 0, 2];
  static const build = 3;
  List<int>? remoteVersion;
  int? remoteBuild;
  bool hasNewVersion = false;
  bool remoteIsBeta = false;

  /// 版本信息文件，托管在本仓库 remote/ 目录，经 jsDelivr 分发
  static const checkUpdateUrl =
      'https://cdn.jsdelivr.net/gh/bno3bno3/Litechron@main/remote/version.json';

  /// 项目主页，也是 version.json 缺少 url 字段时的下载页兜底
  static const projectUrl = 'https://github.com/bno3bno3/Litechron';
  static const releaseUrl = '$projectUrl/releases/latest';

  /// 远程给出的下载页地址，未获取到时回退到 [releaseUrl]
  String? remoteUrl;

  final Future<Map<String, dynamic>> Function()? _fetchVersion;
  final Future<void> Function(Fuse)? _save;
  final Duration _timeout;
  Future<UpdateCheckResult>? _pendingCheck;
  bool _manualCheckRequested = false;

  String get displayVersion => version.join('.') + (isBeta ? ' beta' : '');

  String get downloadUrl => remoteUrl ?? releaseUrl;

  Fuse({
    Future<Map<String, dynamic>> Function()? fetchVersion,
    Future<void> Function(Fuse)? save,
    Duration timeout = const Duration(seconds: 15),
  })  : _fetchVersion = fetchVersion,
        _save = save,
        _timeout = timeout {
    lastUpdateTime = DateTime(2001, 1, 1);
  }

  Future<UpdateCheckResult> checkUpdate({bool force = false}) async {
    if (_pendingCheck != null) {
      if (!force) return UpdateCheckResult.skipped;
      _manualCheckRequested = true;
      return _pendingCheck!;
    }
    if (!force &&
        lastUpdateTime
            .isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
      return UpdateCheckResult.skipped;
    }
    _manualCheckRequested = force;
    final pending = _checkUpdate();
    _pendingCheck = pending;
    try {
      final result = await pending;
      // 手动检查接管结果提示，避免与启动检查同时弹出两个对话框。
      return !force && _manualCheckRequested
          ? UpdateCheckResult.skipped
          : result;
    } finally {
      _pendingCheck = null;
    }
  }

  Future<Map<String, dynamic>> _readVersion() async {
    final client = HttpClient();
    try {
      return await (() async {
        final request = await client.getUrl(Uri.parse(checkUpdateUrl));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw const HttpException('Update check failed');
        }
        final body = await response.transform(utf8.decoder).join();
        return jsonDecode(body) as Map<String, dynamic>;
      })()
          .timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<UpdateCheckResult> _checkUpdate() async {
    try {
      final json =
          await (_fetchVersion?.call() ?? _readVersion()).timeout(_timeout);
      final nextVersion =
          (json['version'] as String).split('.').map(int.parse).toList();
      final nextBuild = json['build'] as int;
      final nextBeta = json['beta'] == true;
      final nextUrl = json['url'] as String?;
      if (nextVersion.length != 3 ||
          nextVersion.any((v) => v < 0) ||
          nextBuild < 0) {
        throw const FormatException('Invalid update version');
      }
      // CDN 节点可能返回旧缓存，不覆盖已经发现的更高版本。
      if (remoteVersion == null ||
          remoteBuild == null ||
          _compare(nextVersion, nextBuild, nextBeta, remoteVersion!,
                  remoteBuild!, remoteIsBeta) >=
              0) {
        remoteVersion = nextVersion;
        remoteBuild = nextBuild;
        remoteIsBeta = nextBeta;
        remoteUrl = nextUrl;
      }
      hasNewVersion = _compareVersion(remoteIsBeta);
      final previousTime = lastUpdateTime;
      lastUpdateTime = DateTime.now();
      try {
        await (_save?.call(this) ??
            Get.find<DatabaseHelper>(tag: 'db').setFuse(this));
      } catch (_) {
        lastUpdateTime = previousTime;
        rethrow;
      }
      return hasNewVersion
          ? UpdateCheckResult.available
          : UpdateCheckResult.upToDate;
    } catch (_) {
      return UpdateCheckResult.failed;
    }
  }

  static int _compare(List<int> a, int aBuild, bool aBeta, List<int> b,
      int bBuild, bool bBeta) {
    for (var i = 0; i < 3; i++) {
      final comparison = a[i].compareTo(b[i]);
      if (comparison != 0) return comparison;
    }
    final comparison = aBuild.compareTo(bBuild);
    if (comparison != 0) return comparison;
    return (aBeta ? 0 : 1).compareTo(bBeta ? 0 : 1);
  }

  bool _compareVersion(bool remoteIsBeta) {
    if (remoteVersion == null || remoteBuild == null) {
      return false;
    }
    if (remoteVersion!.length < 3) {
      return false;
    }
    if (remoteVersion![0] > version[0]) {
      return true;
    } else if (remoteVersion![0] == version[0]) {
      if (remoteVersion![1] > version[1]) {
        return true;
      } else if (remoteVersion![1] == version[1]) {
        if (remoteVersion![2] > version[2]) {
          return true;
        } else if (remoteVersion![2] == version[2]) {
          if (remoteBuild! > build) {
            return true;
          } else if (remoteBuild == build) {
            if (isBeta && !remoteIsBeta) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'lastUpdateTime': lastUpdateTime.toIso8601String(),
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        if (remoteVersion != null) 'remoteVersion': remoteVersion,
        if (remoteBuild != null) 'remoteBuild': remoteBuild,
        'remoteIsBeta': remoteIsBeta,
      };

  Fuse.fromJson(Map<String, dynamic> json)
      : _fetchVersion = null,
        _save = null,
        _timeout = const Duration(seconds: 15) {
    lastUpdateTime = DateTime.parse(json['lastUpdateTime']);
    remoteUrl = json['remoteUrl'] as String?;
    remoteVersion = (json['remoteVersion'] as List?)?.cast<int>();
    remoteBuild = json['remoteBuild'] as int?;
    remoteIsBeta = json['remoteIsBeta'] == true;
    hasNewVersion = _compareVersion(remoteIsBeta);
  }
}
