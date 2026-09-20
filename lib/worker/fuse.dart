import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';

import 'package:celechron/database/database_helper.dart';

class Fuse {
  late DateTime lastUpdateTime;

  final bool isBeta = false;
  final version = [1, 2, 0];
  final build = 1;
  List<int>? remoteVersion;
  int? remoteBuild;
  bool hasNewVersion = false;

  /// 版本信息文件，托管在本仓库 remote/ 目录，经 jsDelivr 分发
  static const checkUpdateUrl =
      'https://cdn.jsdelivr.net/gh/bno3bno3/Litechron@main/remote/version.json';

  /// 项目主页，也是 version.json 缺少 url 字段时的下载页兜底
  static const projectUrl = 'https://github.com/bno3bno3/Litechron';
  static const releaseUrl = '$projectUrl/releases/latest';

  /// 远程给出的下载页地址，未获取到时回退到 [releaseUrl]
  String? remoteUrl;

  final HttpClient _httpClient = HttpClient();
  final DatabaseHelper _db = Get.find<DatabaseHelper>(tag: 'db');

  String get displayVersion => version.join('.') + (isBeta ? ' beta' : '');

  String get downloadUrl => remoteUrl ?? releaseUrl;

  Fuse() {
    lastUpdateTime = DateTime(2001, 1, 1);
  }

  Future<String?> checkUpdate() async {
    try {
      if (lastUpdateTime
          .isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
        return null;
      }

      var request = await _httpClient
          .getUrl(Uri.parse(checkUpdateUrl))
          .timeout(const Duration(seconds: 8));
      var response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return null;
      }
      var body = await response.transform(utf8.decoder).join();
      var json = jsonDecode(body) as Map<String, dynamic>;

      remoteVersion = (json['version'] as String)
          .split('.')
          .map((e) => int.parse(e))
          .toList();
      remoteBuild = json['build'] as int;
      remoteUrl = json['url'] as String?;

      hasNewVersion = _compareVersion(json['beta'] == true);
      lastUpdateTime = DateTime.now();
      await _db.setFuse(this);

      if (hasNewVersion) {
        return "有新版本可用";
      }
      return null;
    } catch (e) {
      return null;
    }
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
      };

  Fuse.fromJson(Map<String, dynamic> json) {
    lastUpdateTime = DateTime.parse(json['lastUpdateTime']);
    remoteUrl = json['remoteUrl'] as String?;
  }
}
