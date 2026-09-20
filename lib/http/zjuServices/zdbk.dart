import 'dart:convert';
import 'dart:io';
import 'package:litechron/utils/tuple.dart';
import 'package:flutter/foundation.dart';

import 'package:litechron/database/database_helper.dart';
import 'package:litechron/utils/gpa_helper.dart';
import 'package:litechron/model/grade.dart';
import 'package:litechron/model/session.dart';
import 'package:litechron/model/exams_dto.dart';
import 'package:litechron/design/captcha_input.dart';
import 'exceptions.dart';

class Zdbk {
  Cookie? _jSessionId;
  Cookie? _route;
  Cookie? _iPlanetDirectoryPro;
  String? _captcha;
  DatabaseHelper? _db;
  Future<void>? _reloginFuture;

  set db(DatabaseHelper? db) {
    _db = db;
  }

  /// 登录教务网。已有登录进行中时直接等待它完成，不并发建立第二个会话：
  /// 教务网同一账号只保留一个会话，重复登录会让并发中的请求被踢下线。
  Future<bool> login(HttpClient httpClient, Cookie? iPlanetDirectoryPro) async {
    if (iPlanetDirectoryPro == null) {
      throw ExceptionWithMessage("iPlanetDirectoryPro无效");
    }
    _iPlanetDirectoryPro = iPlanetDirectoryPro;

    final inFlight = _reloginFuture;
    if (inFlight != null) {
      await inFlight;
      return true;
    }
    final future = _doLogin(httpClient, iPlanetDirectoryPro);
    _reloginFuture = future;
    try {
      await future;
    } finally {
      if (identical(_reloginFuture, future)) {
        _reloginFuture = null;
      }
    }
    return true;
  }

  Future<void> _doLogin(
      HttpClient httpClient, Cookie iPlanetDirectoryPro) async {
    late HttpClientRequest request;
    late HttpClientResponse response;

    request = await httpClient
        .getUrl(Uri.parse(
            "https://zjuam.zju.edu.cn/cas/login?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html"))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));
    request.followRedirects = false;
    request.cookies.add(iPlanetDirectoryPro);
    response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw ExceptionWithMessage("请求超时"));
    response.drain();

    var stLocation = response.headers.value('location');
    if (stLocation == null) {
      throw ExceptionWithMessage("iPlanetDirectoryPro无效");
    } else if (stLocation.startsWith("http://")) {
      stLocation = stLocation.replaceFirst("http://", "https://");
    }
    request = await httpClient.getUrl(Uri.parse(stLocation)).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw ExceptionWithMessage("请求超时"));
    request.followRedirects = false;
    response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw ExceptionWithMessage("请求超时"));
    response.drain();

    final jSessionId = response.cookies
        .where((element) =>
            element.name == 'JSESSIONID' && element.path == '/jwglxt')
        .firstOrNull;
    if (jSessionId == null) {
      throw ExceptionWithMessage("无法获取JSESSIONID");
    }
    final route = response.cookies
        .where((element) => element.name == 'route')
        .firstOrNull;
    if (route == null) {
      throw ExceptionWithMessage("无法获取route");
    }

    // 登录成功后才整套替换，中间没有 await：并发中的请求要么拿到整套旧值、
    // 要么整套新值，不会出现只剩一半的会话
    _jSessionId = jSessionId;
    _route = route;
    _captcha = null;
  }

  void logout() {
    _jSessionId = null;
    _route = null;
    _iPlanetDirectoryPro = null;
    _captcha = null;
    _reloginFuture = null;
  }

  /// 当前会话的两个 Cookie；尚未登录或已登出时视为会话失效
  List<Cookie> _requireSession() {
    final jSessionId = _jSessionId;
    final route = _route;
    if (jSessionId == null || route == null) {
      throw SessionExpiredException();
    }
    return [jSessionId, route];
  }

  void _checkSessionExpired(HttpClientResponse response, String responseText) {
    // 失效会话在这几个查询接口上返回 HTTP 901 且响应体为空，不走重定向，必须单独识别
    if (response.statusCode == 901) {
      throw SessionExpiredException();
    }
    if (response.statusCode == HttpStatus.movedTemporarily ||
        response.statusCode == HttpStatus.movedPermanently ||
        response.statusCode == HttpStatus.found) {
      throw SessionExpiredException();
    }
    if (responseText.contains("login_ssologin") ||
        responseText.contains("cas/login") ||
        responseText.contains("统一身份认证")) {
      throw SessionExpiredException();
    }
  }

  Exception _toException(Object error) {
    if (error is SocketException) return ExceptionWithMessage("网络错误");
    if (error is Exception) return error;
    return ExceptionWithMessage(error.toString());
  }

  // 教务网对课表查询接口按会话限流，触发时返回 HTTP 921"请求过于频繁"。
  // 2026-09 实测：约 1 秒内恢复，且计数按会话（重登即重置）。
  // 因此课表请求被限流时原地退避重试即可，不应重新登录——
  // 教务网同一账号只保留一个会话，重登会让并发进行中的其他抓取被踢下线。
  static Duration rateLimitBackoff = const Duration(milliseconds: 1200);
  static const maxRateLimitRetries = 4;

  static bool _isRateLimited(int statusCode, String responseText) =>
      statusCode == 921 || responseText.contains("请求过于频繁");

  List<Map<String, dynamic>> _getCachedJsonMaps(String key) {
    try {
      final cached = _db?.getCachedWebPage(key);
      if (cached == null) return [];

      final decoded = jsonDecode(cached);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _relogin(HttpClient httpClient) async {
    final iPlanetDirectoryPro = _iPlanetDirectoryPro;
    if (iPlanetDirectoryPro == null) {
      throw ExceptionWithMessage("会话已过期，请重新登录");
    }
    await login(httpClient, iPlanetDirectoryPro);
  }

  /// 用当前会话执行 [action]；会话失效时重登后重试。
  ///
  /// 会话在进入 action 前整套取出并传入，action 内不得再读字段。
  /// 失效时若发现会话已被并发的其他请求换成新的，直接用新会话重试，
  /// 不再重复登录（重复登录会让刚换好的会话又失效）。
  Future<T> _withAutoRelogin<T>(HttpClient httpClient,
      Future<T> Function(List<Cookie> session) action) async {
    for (var i = 0; i < 3; i++) {
      List<Cookie> session;
      try {
        session = _requireSession();
      } on SessionExpiredException {
        await _relogin(httpClient);
        continue;
      }
      try {
        return await action(session);
      } on SessionExpiredException {
        if (identical(_jSessionId, session[0])) {
          await _relogin(httpClient);
        }
      }
    }
    throw ExceptionWithMessage("会话已过期且自动重登失败");
  }

  Future<Tuple<Exception?, Tuple<List<double>, String>>> getMajorGrade(
      HttpClient httpClient) async {
    return await _withAutoRelogin(httpClient, (session) async {
      late HttpClientRequest request;
      late HttpClientResponse response;

      try {
        request = await httpClient
            .postUrl(Uri.parse(
                "https://zdbk.zju.edu.cn/jwglxt/zycjtj/xszgkc_cxXsZgkcIndex.html?doType=query&queryModel.showCount=5000"))
            .timeout(const Duration(seconds: 8),
                onTimeout: () => throw ExceptionWithMessage("请求超时"));
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
          ..add('X-Requested-With', 'XMLHttpRequest');
        request.cookies.addAll(session);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));

        var responseText = await response.transform(utf8.decoder).join();
        _checkSessionExpired(response, responseText);

        if (_isRateLimited(response.statusCode, responseText)) {
          throw ExceptionWithMessage("请求过于频繁，请稍后再试");
        }

        var transcriptJson = RegExp('(?<="items":)\\[(.*?)\\](?=,"limit")')
            .firstMatch(responseText)
            ?.group(0);
        if (transcriptJson == null) throw ExceptionWithMessage("无法解析主修成绩");

        var grades = (jsonDecode(transcriptJson) as List<dynamic>)
            .where((e) => e['xkkh'] != null)
            .map((e) {
          var grade = Grade(e);
          grade.major = true;
          return grade;
        });
        var majorGpa = GpaHelper.calculateGpa(grades);
        _db?.setCachedWebPage('zdbk_MajorGrade', transcriptJson);
        return Tuple(
            null, Tuple([majorGpa.item1[0], majorGpa.item2], responseText));
      } catch (e) {
        if (e is SessionExpiredException) rethrow;
        var exception = _toException(e);
        var cachedItems = _getCachedJsonMaps('zdbk_MajorGrade');
        var grades = cachedItems.where((e) => e['xkkh'] != null).map((e) {
          var grade = Grade(e);
          grade.major = true;
          return grade;
        });
        var majorGpa = GpaHelper.calculateGpa(grades);
        var cachedJson = jsonEncode(cachedItems);
        return Tuple(
            exception,
            Tuple([majorGpa.item1[0], majorGpa.item2],
                '{"items":$cachedJson,"limit":0}'));
      }
    });
  }

  Future<Tuple<Exception?, Iterable<Grade>>> getTranscript(
      HttpClient httpClient) async {
    return await _withAutoRelogin(httpClient, (session) async {
      late HttpClientRequest request;
      late HttpClientResponse response;

      try {
        request = await httpClient
            .postUrl(Uri.parse(
                "https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000"))
            .timeout(const Duration(seconds: 8),
                onTimeout: () => throw ExceptionWithMessage("请求超时"));
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
          ..add('X-Requested-With', 'XMLHttpRequest');
        request.cookies.addAll(session);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));

        var responseText = await response.transform(utf8.decoder).join();
        _checkSessionExpired(response, responseText);

        if (_isRateLimited(response.statusCode, responseText)) {
          throw ExceptionWithMessage("请求过于频繁，请稍后再试");
        }

        var transcriptJson = RegExp('(?<="items":)\\[(.*?)\\](?=,"limit")')
            .firstMatch(responseText)
            ?.group(0);
        if (transcriptJson == null) throw ExceptionWithMessage("无法解析成绩");

        var grades = (jsonDecode(transcriptJson) as List<dynamic>)
            .where((e) => e['xkkh'] != null)
            .map((e) => Grade(e));
        _db?.setCachedWebPage('zdbk_Transcript', transcriptJson);
        return Tuple(null, grades);
      } catch (e) {
        if (e is SessionExpiredException) rethrow;
        var exception = _toException(e);
        return Tuple(
            exception,
            _getCachedJsonMaps('zdbk_Transcript')
                .where((e) => e['xkkh'] != null)
                .map((e) => Grade(e)));
      }
    });
  }

  Future<Tuple<Exception?, Iterable<Session>>> getTimetable(
      HttpClient httpClient, String year, String semester,
      {bool allowUserInteraction = false}) async {
    return await _withAutoRelogin(httpClient, (session) async {
      late HttpClientRequest request;
      late HttpClientResponse response;

      try {
        var captchaRounds = 0;
        var rateLimitRetries = 0;
        while (true) {
          request = await httpClient
              .postUrl(Uri.parse(
                  "https://zdbk.zju.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html"))
              .timeout(const Duration(seconds: 8),
                  onTimeout: () => throw ExceptionWithMessage("请求超时"));
          request.headers
            ..add("Referer",
                "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
            ..add('X-Requested-With', 'XMLHttpRequest');
          request.cookies.addAll(session);
          request.headers.contentType = ContentType(
              'application', 'x-www-form-urlencoded',
              charset: 'utf-8');
          request.add(
              utf8.encode('xnm=$year&xqm=$semester&captcha_value=$_captcha'));
          response = await request.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw ExceptionWithMessage("请求超时"));

          var responseText = await response.transform(utf8.decoder).join();
          _checkSessionExpired(response, responseText);

          if (_isRateLimited(response.statusCode, responseText)) {
            if (++rateLimitRetries > maxRateLimitRetries) {
              throw ExceptionWithMessage("教务网限流，请求过于频繁，请稍后重试");
            }
            await Future.delayed(rateLimitBackoff);
            continue;
          }

          if (responseText.contains("captcha_error")) {
            _captcha = null;
            if (++captchaRounds > 3) {
              throw ExceptionWithMessage("验证码识别失败");
            }
            if (!allowUserInteraction) {
              throw ExceptionWithMessage("需要验证码");
            }
            var imageBytes = await getCaptcha(httpClient, session: session);
            var captcha = await ImageCodePortal.show(
                imageBytes: imageBytes,
                onRefresh: () async {
                  return await getCaptcha(httpClient, session: session);
                });
            if (captcha == null) {
              throw ExceptionWithMessage("验证码未填写");
            }
            _captcha = captcha.trim();
            continue;
          }

          if (responseText == "null") return Tuple(null, []);
          var kbList = _extractKbList(responseText);
          if (kbList == null) {
            throw ExceptionWithMessage("无法解析课表（HTTP ${response.statusCode}）");
          }
          _db?.setCachedWebPage(
              'zdbk_Timetable$year$semester', jsonEncode(kbList));
          var sessions = kbList
              .where((e) => e['kcb'] != null && (e['sfyjskc'] != "1"))
              .map((e) => Session.fromZdbk(e));
          return Tuple(null, sessions);
        }
      } catch (e) {
        if (e is SessionExpiredException) rethrow;
        var exception = _toException(e);
        return Tuple(
            exception,
            _getCachedJsonMaps('zdbk_Timetable$year$semester')
                .where((e) => e['kcb'] != null && e['sfyjskc'] != "1")
                .map((e) => Session.fromZdbk(e)));
      }
    });
  }

  // 优先把整个响应当作 JSON 解析后取 kbList（对教务网调整字段顺序健壮），
  // 失败时退回旧版的正则提取
  static List<dynamic>? _extractKbList(String responseText) {
    try {
      final decoded = jsonDecode(responseText);
      if (decoded is Map && decoded['kbList'] is List) {
        return decoded['kbList'] as List<dynamic>;
      }
    } catch (_) {}
    var timetableJson = RegExp('(?<="kbList":)\\[(.*?)\\](?=,"xh")')
        .firstMatch(responseText)
        ?.group(0);
    if (timetableJson == null) return null;
    try {
      return jsonDecode(timetableJson) as List<dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Tuple<Exception?, Iterable<ExamDto>>> getExamsDto(
      HttpClient httpClient) async {
    return await _withAutoRelogin(httpClient, (session) async {
      late HttpClientRequest request;
      late HttpClientResponse response;

      try {
        request = await httpClient
            .postUrl(Uri.parse(
                "https://zdbk.zju.edu.cn/jwglxt/xskscx/kscx_cxXsgrksIndex.html?doType=query&queryModel.showCount=5000"))
            .timeout(const Duration(seconds: 8),
                onTimeout: () => throw ExceptionWithMessage("请求超时"));
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
          ..add('X-Requested-With', 'XMLHttpRequest');
        request.cookies.addAll(session);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));

        var responseText = await response.transform(utf8.decoder).join();
        _checkSessionExpired(response, responseText);

        if (_isRateLimited(response.statusCode, responseText)) {
          throw ExceptionWithMessage("请求过于频繁，请稍后再试");
        }

        var transcriptJson = RegExp('(?<="items":)\\[(.*?)\\](?=,"limit")')
            .firstMatch(responseText)
            ?.group(0);
        if (transcriptJson == null) throw ExceptionWithMessage("无法解析考试信息");

        var exams = (jsonDecode(transcriptJson) as List<dynamic>)
            .where((e) => e['xkkh'] != null)
            .map((e) => ExamDto.fromZdbk(e));
        _db?.setCachedWebPage('zdbk_exams', transcriptJson);
        return Tuple(null, exams);
      } catch (e) {
        if (e is SessionExpiredException) rethrow;
        var exception = _toException(e);
        return Tuple(
            exception,
            _getCachedJsonMaps('zdbk_exams')
                .where((e) => e['xkkh'] != null)
                .map((e) => ExamDto.fromZdbk(e)));
      }
    });
  }

  Future<Tuple<Exception?, Map<String, double>>> getPracticeScores(
      HttpClient httpClient, String studentId) async {
    return await _withAutoRelogin(httpClient, (session) async {
      late HttpClientRequest request;
      late HttpClientResponse response;

      try {
        request = await httpClient
            .getUrl(Uri.parse(
                "https://zdbk.zju.edu.cn/jwglxt/dessktgl/dessktcx_cxDessktcxIndex.html?gnmkdm=N108001&layout=default&su=$studentId"))
            .timeout(const Duration(seconds: 8),
                onTimeout: () => throw ExceptionWithMessage("请求超时"));
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept',
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
        request.cookies.addAll(session);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));

        var html = await response.transform(utf8.decoder).join();
        _checkSessionExpired(response, html);

        _db?.setCachedWebPage("zdbk_practiceScores", html);

        var scores = <String, double>{
          'pt2': 0.0,
          'pt3': 0.0,
          'pt4': 0.0,
        };

        var rowPattern = RegExp(
            r'<tr>.*?<td[^>]*>.*?</td>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?</tr>',
            dotAll: true);
        var matches = rowPattern.allMatches(html);

        for (var match in matches) {
          var type = match.group(1)?.trim();
          var scoreStr = match.group(2)?.trim();
          if (type == null || scoreStr == null) continue;

          double? score;
          try {
            score = double.tryParse(scoreStr);
          } catch (_) {
            continue;
          }
          if (score == null) continue;

          if (type.contains('第二课堂')) {
            scores['pt2'] = score;
          } else if (type.contains('第三课堂')) {
            scores['pt3'] = score;
          } else if (type.contains('第四课堂')) {
            scores['pt4'] = score;
          }
        }

        if (scores['pt2'] == 0.0 &&
            scores['pt3'] == 0.0 &&
            scores['pt4'] == 0.0) {
          var altPattern = RegExp(
              r'<td[^>]*>第二课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
              dotAll: true);
          var pt2Match = altPattern.firstMatch(html);
          if (pt2Match != null) {
            scores['pt2'] = double.tryParse(pt2Match.group(1) ?? '0') ?? 0.0;
          }

          altPattern = RegExp(r'<td[^>]*>第三课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
              dotAll: true);
          var pt3Match = altPattern.firstMatch(html);
          if (pt3Match != null) {
            scores['pt3'] = double.tryParse(pt3Match.group(1) ?? '0') ?? 0.0;
          }

          altPattern = RegExp(r'<td[^>]*>第四课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
              dotAll: true);
          var pt4Match = altPattern.firstMatch(html);
          if (pt4Match != null) {
            scores['pt4'] = double.tryParse(pt4Match.group(1) ?? '0') ?? 0.0;
          }
        }

        return Tuple(null, scores);
      } catch (e) {
        if (e is SessionExpiredException) rethrow;

        var exception = _toException(e);

        var cachedHtml = _db?.getCachedWebPage("zdbk_practiceScores");
        if (cachedHtml != null) {
          try {
            var scores = <String, double>{
              'pt2': 0.0,
              'pt3': 0.0,
              'pt4': 0.0,
            };
            var altPattern = RegExp(
                r'<td[^>]*>第二课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
                dotAll: true);
            var pt2Match = altPattern.firstMatch(cachedHtml);
            if (pt2Match != null) {
              scores['pt2'] = double.tryParse(pt2Match.group(1) ?? '0') ?? 0.0;
            }

            altPattern = RegExp(r'<td[^>]*>第三课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
                dotAll: true);
            var pt3Match = altPattern.firstMatch(cachedHtml);
            if (pt3Match != null) {
              scores['pt3'] = double.tryParse(pt3Match.group(1) ?? '0') ?? 0.0;
            }

            altPattern = RegExp(r'<td[^>]*>第四课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
                dotAll: true);
            var pt4Match = altPattern.firstMatch(cachedHtml);
            if (pt4Match != null) {
              scores['pt4'] = double.tryParse(pt4Match.group(1) ?? '0') ?? 0.0;
            }
            return Tuple(exception, scores);
          } catch (_) {}
        }
        return Tuple(exception, {'pt2': 0.0, 'pt3': 0.0, 'pt4': 0.0});
      }
    });
  }

  /// 获取验证码图片。[session] 缺省时用当前会话，未登录则报错
  Future<Uint8List> getCaptcha(HttpClient httpClient,
      {List<Cookie>? session}) async {
    late HttpClientRequest request;
    late HttpClientResponse response;

    List<Cookie> cookies;
    try {
      cookies = session ?? _requireSession();
    } on SessionExpiredException {
      throw ExceptionWithMessage("未登录");
    }
    request = await httpClient
        .getUrl(Uri.parse(
            "https://zdbk.zju.edu.cn/jwglxt/kaptcha?time=${DateTime.now().millisecondsSinceEpoch}"))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));
    request.cookies.addAll(cookies);
    request.followRedirects = false;
    response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw ExceptionWithMessage("请求超时"));
    var bytes = await consolidateHttpClientResponseBytes(response);
    return bytes;
  }

  Future<String> solveCaptcha(HttpClient httpClient) async {
    throw UnimplementedError("验证码识别功能未开发");
  }
}
