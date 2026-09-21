import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:litechron/http/zjuServices/zdbk.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-09 实测：教务网课表查询接口按会话限流，触发时返回
// HTTP 921"请求过于频繁，请稍后再试！"；会话失效时返回 HTTP 901 空响应体。
void main() {
  setUp(() {
    Zdbk.reloginBackoff = Duration.zero;
  });
  tearDown(() {
    Zdbk.rateLimitBackoff = const Duration(milliseconds: 1200);
    Zdbk.reloginBackoff = const Duration(milliseconds: 1500);
  });

  test('921限流时退避后原会话重试，成功后正常解析', () async {
    Zdbk.rateLimitBackoff = Duration.zero;
    final client = _ScriptedClient([
      ..._loginResponses(),
      _Response.text('"请求过于频繁，请稍后再试！"', statusCode: 921),
      _Response.text(_timetableBody()),
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));

    final result = await zdbk.getTimetable(client, '2025-2026', '1|秋');

    expect(result.item1, isNull);
    final sessions = result.item2.toList();
    expect(sessions, hasLength(1));
    expect(sessions.first.name, '测试课程');
    expect(sessions.first.teacher, '测试教师');
    expect(sessions.first.location, '紫金港东1-101');
    // 限流重试不重新登录：仍然只有最初 2 次登录请求 + 2 次课表请求
    expect(client.requests, hasLength(4));
    expect(
        client.requests.where((r) => r.uri.path.endsWith('xskbcx_cxXsKb.html')),
        hasLength(2));
  });

  test('连续限流超过上限时报限流错误并返回缓存', () async {
    Zdbk.rateLimitBackoff = Duration.zero;
    final client = _ScriptedClient([
      ..._loginResponses(),
      for (var i = 0; i < 6; i++) _Response.text('请求过于频繁', statusCode: 921),
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));

    final result = await zdbk.getTimetable(client, '2025-2026', '1|秋');

    expect(result.item1.toString(), contains('请求过于频繁'));
    expect(result.item2, isEmpty);
    // 最初一次 + maxRateLimitRetries 次重试
    expect(client.requests, hasLength(2 + 1 + Zdbk.maxRateLimitRetries));
  });

  test('901会话失效时自动用原SSO凭据重登并重试', () async {
    final client = _ScriptedClient([
      ..._loginResponses(),
      _Response.text('', statusCode: 901),
      ..._loginResponses(),
      _Response.text(_timetableBody()),
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));

    final result = await zdbk.getTimetable(client, '2025-2026', '1|秋');

    expect(result.item1, isNull);
    expect(result.item2.toList(), hasLength(1));
    // 初始登录2次 + 课表901一次 + 自动重登2次 + 重试成功1次
    expect(client.requests, hasLength(6));
  });

  test('课表被反复顶掉：重登次数用尽后抛错，交给上层整套重登', () async {
    final client = _ScriptedClient([
      ..._loginResponses(),
      for (var i = 0; i < Zdbk.timetableReloginAttempts; i++) ...[
        _Response.text('', statusCode: 901),
        if (i + 1 < Zdbk.timetableReloginAttempts) ..._loginResponses(),
      ],
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));

    await expectLater(
        zdbk.getTimetable(client, '2025-2026', '1|秋'),
        throwsA(predicate(
            (e) => e.toString() == '会话已过期且自动重登失败')));
    expect(client.responses, isEmpty);
    expect(
        client.requests.where((r) => r.uri.path.endsWith('xskbcx_cxXsKb.html')),
        hasLength(Zdbk.timetableReloginAttempts));
  });

  // 回归：以前 login() 一开始就把会话字段清空，登录期间并发的请求会在
  // `_jSessionId!` 上抛 "Null check operator used on a null value"
  test('登录进行中时并发请求沿用旧会话，失效后改用新会话重试且不重复登录', () async {
    final client = _ScriptedClient([
      ..._loginResponses(), // 初始登录 → 会话 A
      _loginResponses()[0], // 并发登录第 1 步（CAS 重定向）
      _Response.text('', statusCode: 901), // 课表带会话 A → 已被新登录顶掉
      _Response.text('', cookies: [
        Cookie('JSESSIONID', 'session-b')..path = '/jwglxt',
        Cookie('route', 'route-b'),
      ]), // 并发登录第 2 步 → 会话 B
      _Response.text(_timetableBody()), // 课表带会话 B → 成功
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));

    final relogin =
        zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));
    final result = await zdbk.getTimetable(client, '2025-2026', '1|秋');
    await relogin;

    expect(result.item1, isNull);
    expect(result.item2.toList(), hasLength(1));
    expect(client.requests, hasLength(6));
    expect(client.responses, isEmpty);
    final timetableRequests = client.requests
        .where((r) => r.uri.path.endsWith('xskbcx_cxXsKb.html'))
        .toList();
    expect(timetableRequests, hasLength(2));
    expect(timetableRequests.first.cookies.map((c) => c.value),
        contains('test-session'));
    expect(timetableRequests.last.cookies.map((c) => c.value),
        contains('session-b'));
  });

  test('同一时刻多次登录只发一组登录请求', () async {
    final client = _ScriptedClient([
      ..._loginResponses(),
      _Response.text(_timetableBody()),
    ]);
    final zdbk = Zdbk();
    final sso = Cookie('iPlanetDirectoryPro', 'test-sso');

    await Future.wait([
      zdbk.login(client, sso),
      zdbk.login(client, sso),
      zdbk.login(client, sso),
    ]);
    final result = await zdbk.getTimetable(client, '2025-2026', '1|秋');

    expect(result.item1, isNull);
    expect(client.requests, hasLength(3));
  });

  test('kbList不在xh前（字段顺序变化）时仍能解析', () async {
    // 老正则要求 kbList 后紧跟 "xh"，此响应故意把 xh 放在前面，只有 JSON 解析路径能通过
    final body = jsonEncode({
      'xh': '3230100000',
      'kbList': [_kbEntry()]
    });
    final client = _ScriptedClient([
      ..._loginResponses(),
      _Response.text(body),
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));

    final result = await zdbk.getTimetable(client, '2025-2026', '1|秋');

    expect(result.item1, isNull);
    expect(result.item2.toList(), hasLength(1));
  });

  test('响应不是纯JSON时退回旧版正则解析', () async {
    final entryJson = jsonEncode(_kbEntry());
    final body =
        'garbage-prefix{"kbList":[$entryJson],"xh":"3230100000"}suffix';
    final client = _ScriptedClient([
      ..._loginResponses(),
      _Response.text(body),
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));

    final result = await zdbk.getTimetable(client, '2025-2026', '1|秋');

    expect(result.item1, isNull);
    expect(result.item2.toList(), hasLength(1));
  });
}

Map<String, dynamic> _kbEntry({String? sfyjskc}) => {
      'sfqd': '1',
      'xqj': '1',
      'dsz': '2',
      'xxq': '秋',
      'djj': '2',
      'skcd': '2',
      'kcb':
          '测试课程<br>秋冬{第1-8周|1节/周}<br>测试教师<br>紫金港东1-101zwf2026年01月16日(08:00-10:00)zwf紫金港机房',
      'xkkh': '(2025-2026-1)-TEST0001-0000000-1',
      if (sfyjskc != null) 'sfyjskc': sfyjskc,
    };

String _timetableBody() => jsonEncode({
      'kbList': [
        _kbEntry(),
        _kbEntry(sfyjskc: '1'), // 研究生课程，应被过滤
      ],
      'xh': '3230100000',
    });

List<_Response> _loginResponses() => [
      _Response.text('', statusCode: HttpStatus.found, headers: {
        'location': 'https://zdbk.zju.edu.cn/jwglxt/xtgl/login_ssologin.html',
      }),
      _Response.text('', cookies: [
        Cookie('JSESSIONID', 'test-session')..path = '/jwglxt',
        Cookie('route', 'test-route'),
      ]),
    ];

// 只消费脚本中的响应，不创建真实 HttpClient 或发起网络请求。
class _ScriptedClient extends Fake implements HttpClient {
  _ScriptedClient(List<_Response> responses) : responses = Queue.of(responses);

  final Queue<_Response> responses;
  final requests = <_Request>[];

  Future<HttpClientRequest> _open(Uri uri) async {
    final request = _Request(uri, responses.removeFirst());
    requests.add(request);
    return request;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _open(url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _open(url);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.uri, this.response);

  @override
  final Uri uri;
  final _Response response;
  final body = <int>[];
  @override
  final headers = _Headers({});
  @override
  final cookies = <Cookie>[];
  @override
  bool followRedirects = true;

  @override
  void add(List<int> data) => body.addAll(data);

  @override
  Future<HttpClientResponse> close() async => response;
}

class _Headers extends Fake implements HttpHeaders {
  _Headers(this.values);

  final Map<String, String> values;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      add(name, value);

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  ContentType? contentType;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body,
      {this.statusCode = HttpStatus.ok,
      Map<String, String> headers = const {},
      this.cookies = const []})
      : headers = _Headers(Map.of(headers));

  _Response.text(String text,
      {int statusCode = HttpStatus.ok,
      Map<String, String> headers = const {},
      List<Cookie> cookies = const []})
      : this(utf8.encode(text),
            statusCode: statusCode, headers: headers, cookies: cookies);

  final List<int> body;
  @override
  final int statusCode;
  @override
  final _Headers headers;
  @override
  final List<Cookie> cookies;
  @override
  int get contentLength => body.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream.value(body).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
