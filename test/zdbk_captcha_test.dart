import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:litechron/http/zjuServices/zdbk.dart';
import 'package:litechron/utils/global.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('自动请求不弹验证码，随后手动请求可填写验证码并继续抓取', (tester) async {
    await _showApp(tester);
    final client = _ScriptedClient([
      ..._loginResponses(),
      _Response.text('captcha_error'),
      _Response.text('captcha_error'),
      _captchaImage(),
      _Response.text('null'),
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));

    final automatic = await zdbk.getTimetable(client, '2025-2026', '1|秋');
    await tester.pump();
    expect(automatic.item1.toString(), contains('需要验证码'));
    expect(find.text('安全验证'), findsNothing);
    expect(client.requests, hasLength(3));
    expect(
        client.requests.where((r) => r.uri.path.endsWith('/kaptcha')), isEmpty);

    final manual = zdbk.getTimetable(client, '2025-2026', '1|秋',
        allowUserInteraction: true);
    await tester.pumpAndSettle();
    expect(find.text('安全验证'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField), '1234');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect((await manual).item1, isNull);
    expect(find.text('安全验证'), findsNothing);
    expect(
        utf8.decode(client.requests.last.body), contains('captcha_value=1234'));
    expect(client.responses, isEmpty);
  });

  testWidgets('手动取消验证码返回实际失败，不继续请求验证码', (tester) async {
    await _showApp(tester);
    final client = _ScriptedClient([
      ..._loginResponses(),
      _Response.text('captcha_error'),
      _captchaImage(),
    ]);
    final zdbk = Zdbk();
    await zdbk.login(client, Cookie('iPlanetDirectoryPro', 'test-sso'));
    final manual = zdbk.getTimetable(client, '2025-2026', '1|秋',
        allowUserInteraction: true);
    await tester.pumpAndSettle();
    expect(find.text('安全验证'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await manual).item1.toString(), contains('验证码未填写'));
    expect(find.text('安全验证'), findsNothing);
    expect(client.requests, hasLength(4));
  });
}

Future<void> _showApp(WidgetTester tester) => tester.pumpWidget(CupertinoApp(
      navigatorKey: navigatorKey,
      home: const CupertinoPageScaffold(child: Text('验证码测试')),
    ));

List<_Response> _loginResponses() => [
      _Response.text('', statusCode: HttpStatus.found, headers: {
        'location': 'https://zdbk.zju.edu.cn/jwglxt/xtgl/login_ssologin.html',
      }),
      _Response.text('', cookies: [
        Cookie('JSESSIONID', 'test-session')..path = '/jwglxt',
        Cookie('route', 'test-route'),
      ]),
    ];

_Response _captchaImage() => _Response(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));

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
