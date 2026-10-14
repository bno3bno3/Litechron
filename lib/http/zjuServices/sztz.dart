// CAS/context and getSqjl flow adapted from Celechron/Celechron (GPL-3.0).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/model/practice_details.dart';
import 'package:litechron/model/practice_score_item.dart';
import 'package:litechron/utils/json_utils.dart';

import 'exceptions.dart';

/// Lazily authenticated details client; never participates in getEverything.
class Sztz {
  static final _service = Uri.parse('https://sztz.zju.edu.cn/dekt/');
  static final _context = _service.resolve('ctx');
  static final _details = _service.resolve('student/home/getSqjl');
  static const _timeout = Duration(seconds: 12);

  final String account;
  DatabaseHelper? db;
  final _cookies = <_StoredCookie>[];
  bool _authenticated = false;
  int _generation = 0;
  Future<PracticeDetails>? _fetch;

  Sztz({required this.account, this.db});

  static String cacheKey(String account) =>
      'sztz_practice_details_v1_${sha256.convert(utf8.encode(account))}';

  static PracticeDetails readCache(DatabaseHelper? db, String account) {
    try {
      final raw = db?.getCachedWebPage(cacheKey(account));
      if (raw == null) return const PracticeDetails();
      final json = asStringMap(jsonDecode(raw));
      if (json == null || json['version'] != 1 || json['items'] is! List) {
        return const PracticeDetails();
      }
      final date = asDateTime(json['updatedAt']);
      if (date == null) return const PracticeDetails();
      final items = (json['items'] as List)
          .map((value) => PracticeScoreItem.fromJson(asStringMap(value)!))
          .where((item) => !item.deleted)
          .toList();
      return PracticeDetails(
          items: items, updatedAt: date, complete: json['complete'] != false);
    } on Object {
      return const PracticeDetails();
    }
  }

  Future<PracticeDetails> getPracticeDetails(
      HttpClient client, Future<Cookie?> Function(bool fresh) sso) async {
    final pending = _fetch;
    if (pending != null) return pending;
    final future = _getDetails(client, sso, _generation);
    _fetch = future;
    try {
      return await future;
    } finally {
      if (identical(_fetch, future)) _fetch = null;
    }
  }

  Future<PracticeDetails> _getDetails(HttpClient client,
      Future<Cookie?> Function(bool fresh) sso, int generation) async {
    var stage = '素质拓展登录';
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (!_authenticated) {
          stage = '素质拓展登录';
          final cookie =
              await sso(attempt > 0).timeout(const Duration(seconds: 40));
          if (cookie == null) throw const _AuthenticationFailure();
          await _login(client, cookie);
        }
        stage = '实践明细获取';
        final body = await _request(client, _details);
        stage = '实践明细读取';
        Map<String, dynamic>? payload;
        try {
          payload = asStringMap(jsonDecode(body));
        } on FormatException {
          if (body.trimLeft().startsWith('<')) {
            throw const _AuthenticationFailure();
          }
          rethrow;
        }
        if (payload == null ||
            payload['success'] != true ||
            asInt(payload['code']) != 0 ||
            payload['data'] is! List) {
          throw const FormatException();
        }
        var parseFailures = 0;
        final items = PracticeScoreItem.parseSztzItems(payload['data'] as List,
            onError: (_, __, ___) => parseFailures++);
        if (parseFailures > 0) {
          throw _SafeFailure('有 $parseFailures 条记录格式异常');
        }
        if (generation != _generation) return const PracticeDetails();
        final result = PracticeDetails(
            items: items,
            updatedAt: DateTime.now(),
            complete: (asInt(payload['totalPages']) ?? 1) <= 1);
        stage = '实践明细保存';
        await db?.setCachedWebPage(
            cacheKey(account),
            jsonEncode({
              'version': 1,
              'updatedAt': result.updatedAt!.toIso8601String(),
              'complete': result.complete,
              'items': items.map((item) => item.toJson()).toList(),
            }));
        return result;
      } on _AuthenticationFailure {
        _authenticated = false;
        if (attempt == 0 && generation == _generation) continue;
        return readCache(db, account).withError('素质拓展登录失败：登录状态已过期');
      } on Object catch (error) {
        return readCache(db, account).withError('$stage失败：${_reason(error)}');
      }
    }
    return readCache(db, account).withError('实践明细刷新失败：未知错误');
  }

  Future<void> _login(HttpClient client, Cookie sso) async {
    // Consume a fresh CAS ticket, save the business SESSION, then verify ctx.
    final cas = Uri.https(
        'zjuam.zju.edu.cn', '/cas/login', {'service': _service.toString()});
    final request = await client.getUrl(cas).timeout(_timeout);
    request.followRedirects = false;
    request.cookies.add(Cookie(sso.name, sso.value));
    final response = await request.close().timeout(_timeout);
    final location = response.headers.value(HttpHeaders.locationHeader);
    await _read(response);
    if (!_isRedirect(response.statusCode) || location == null) {
      if (response.statusCode == 200 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        throw const _AuthenticationFailure();
      }
      throw _SafeFailure('服务器返回 HTTP ${response.statusCode}');
    }
    final callback = cas.resolve(location);
    if (callback.scheme != _service.scheme ||
        callback.host != _service.host ||
        callback.port != _service.port ||
        callback.path != _service.path ||
        (callback.queryParameters['ticket'] ?? '').isEmpty) {
      throw const _SafeFailure('登录回调无效');
    }
    _cookies.clear();
    _storeCookie(sso, _service, forcedDomain: 'zju.edu.cn');
    await _request(client, callback);
    if (!_cookies.any((cookie) =>
        cookie.cookie.name == 'SESSION' && cookie.matches(_context))) {
      throw const _AuthenticationFailure();
    }
    final body = await _request(client, _context, post: true);
    if (!isAuthenticatedContext(body)) throw const _AuthenticationFailure();
    _authenticated = true;
  }

  static bool isAuthenticatedContext(String body) {
    try {
      final payload = asStringMap(jsonDecode(body));
      if (payload == null ||
          payload['success'] != true ||
          asInt(payload['code']) != 0) {
        return false;
      }
      final encoded = asString(payload['data']);
      if (encoded == null) return false;
      final context = asStringMap(
          jsonDecode(utf8.decode(base64.decode(base64.normalize(encoded)))));
      if (context == null || asBool(context['anonymous']) != false) {
        return false;
      }
      final user = asString(context['userId'])?.trim();
      return user != null &&
          user.isNotEmpty &&
          user.toUpperCase() != 'ANONYMOUS' &&
          !_hasAnonymousRole(context['roles']);
    } on Object {
      return false;
    }
  }

  static bool _hasAnonymousRole(Object? roles) {
    if (roles is List) return roles.any(_hasAnonymousRole);
    if (roles is Map) return roles.values.any(_hasAnonymousRole);
    return (asString(roles) ?? '')
        .split(RegExp(r'[\s,;]+'))
        .contains('ANONYMOUS_USER_ROLE');
  }

  Future<String> _request(HttpClient client, Uri uri,
      {bool post = false}) async {
    final request = await (post ? client.postUrl(uri) : client.getUrl(uri))
        .timeout(_timeout);
    request.followRedirects = false;
    request.headers
      ..set(
          HttpHeaders.acceptHeader,
          post
              ? 'application/json, text/plain, */*'
              : 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (post) {
      request.headers
        ..set(
            HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded')
        ..set('Origin', 'https://sztz.zju.edu.cn')
        ..set(HttpHeaders.refererHeader, _service.toString());
      request.contentLength = 0;
    }
    _cookies.removeWhere((cookie) => cookie.expired);
    request.cookies.addAll(_cookies
        .where((cookie) => cookie.matches(uri))
        .map((cookie) => Cookie(cookie.cookie.name, cookie.cookie.value)));
    final response = await request.close().timeout(_timeout);
    for (final cookie in response.cookies) {
      _storeCookie(cookie, uri);
    }
    final body = await _read(response);
    if (_isRedirect(response.statusCode) ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      throw const _AuthenticationFailure();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw _SafeFailure('服务器返回 HTTP ${response.statusCode}');
    }
    return body;
  }

  Future<String> _read(HttpClientResponse response) =>
      response.transform(utf8.decoder).join().timeout(_timeout);

  void _storeCookie(Cookie cookie, Uri origin, {String? forcedDomain}) {
    final rawDomain = forcedDomain ?? cookie.domain;
    final hostOnly = rawDomain == null || rawDomain.isEmpty;
    final domain = (hostOnly ? origin.host : rawDomain)
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.'), '');
    if (origin.host != domain && !origin.host.endsWith('.$domain')) return;
    final lastSlash = origin.path.lastIndexOf('/');
    final path = (cookie.path ?? '').isNotEmpty
        ? cookie.path!
        : lastSlash <= 0
            ? '/'
            : origin.path.substring(0, lastSlash);
    _cookies.removeWhere((stored) =>
        stored.cookie.name == cookie.name &&
        stored.domain == domain &&
        stored.path == path);
    final stored =
        _StoredCookie(cookie, domain, path, hostOnly, DateTime.now());
    if (!stored.expired) _cookies.add(stored);
  }

  void logout() {
    _generation++;
    _cookies.clear();
    _authenticated = false;
    _fetch = null;
  }

  static bool _isRedirect(int status) =>
      const [301, 302, 303, 307, 308].contains(status);

  static String _reason(Object error) {
    if (error is _SafeFailure) return error.reason;
    if (error is TimeoutException) return '请求超时';
    if (error is SocketException || error is HttpException) return '无法连接服务器';
    if (error is HandshakeException) return '无法建立安全连接';
    if (error is FormatException) return '返回的数据格式异常';
    if (error is LoginException) return '统一身份认证未成功，请检查账号与密码';
    if (error is ExceptionWithMessage) {
      if (error.message == '网络错误') return '无法连接服务器';
      if (error.message == '请求超时') return '请求超时';
    }
    return '未知错误';
  }
}

class _StoredCookie {
  final Cookie cookie;
  final String domain;
  final String path;
  final bool hostOnly;
  final DateTime createdAt;
  _StoredCookie(
      this.cookie, this.domain, this.path, this.hostOnly, this.createdAt);

  bool get expired =>
      (cookie.expires != null && !cookie.expires!.isAfter(DateTime.now())) ||
      (cookie.maxAge != null &&
          !createdAt
              .add(Duration(seconds: cookie.maxAge!))
              .isAfter(DateTime.now()));

  bool matches(Uri uri) =>
      !expired &&
      (!cookie.secure || uri.scheme == 'https') &&
      (hostOnly
          ? uri.host == domain
          : uri.host == domain || uri.host.endsWith('.$domain')) &&
      (uri.path == path ||
          (uri.path.startsWith(path) &&
              (path.endsWith('/') || uri.path[path.length] == '/')));
}

class _AuthenticationFailure implements Exception {
  const _AuthenticationFailure();
}

class _SafeFailure implements Exception {
  final String reason;
  const _SafeFailure(this.reason);
}
