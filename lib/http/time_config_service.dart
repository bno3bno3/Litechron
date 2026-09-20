import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'package:litechron/http/zjuServices/exceptions.dart';
import 'package:litechron/utils/tuple.dart';

import 'package:litechron/database/database_helper.dart';

/// 校历配置（节次时间、学期起止、假期与调休）。
///
/// 读取顺序：远程接口 → Hive 缓存 → 随 App 打包的 assets/calendar/<学期>.json。
/// 远程接口属于上游 Celechron，随时可能失效；内置文件保证已知学期在断网或
/// 接口失效时仍能生成课表。新学期文件需手动加入 assets/calendar/。
class TimeConfigService {
  DatabaseHelper? _db;

  set db(DatabaseHelper? db) {
    _db = db;
  }

  Future<Tuple<Exception?, String?>> getConfig(
      HttpClient httpClient, String semesterId) async {
    try {
      var response = await httpClient
          .getUrl(Uri.parse('http://calendar.celechron.top/$semesterId.json'))
          .then((request) => request.close())
          .timeout(const Duration(seconds: 8),
              onTimeout: () => throw ExceptionWithMessage("请求超时"));

      if (response.statusCode == 200) {
        var config = await response.transform(utf8.decoder).join();
        _db?.setCachedWebPage('timeConfig_$semesterId', config);
        return Tuple(null, config);
      } else {
        return Tuple(null, await _fallback(semesterId));
      }
    } catch (e) {
      var exception =
          e is SocketException ? ExceptionWithMessage("网络错误") : e as Exception;
      return Tuple(exception, await _fallback(semesterId));
    }
  }

  Future<String?> _fallback(String semesterId) async {
    var cached = _db?.getCachedWebPage('timeConfig_$semesterId');
    if (cached != null) return cached;
    return _loadBundled(semesterId);
  }

  Future<String?> _loadBundled(String semesterId) async {
    try {
      return await rootBundle.loadString('assets/calendar/$semesterId.json');
    } catch (_) {
      return null;
    }
  }
}
