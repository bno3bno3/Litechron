import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/model/practice_details.dart';
import 'package:litechron/model/practice_score_item.dart';
import 'package:litechron/model/scholar.dart';

Map<String, dynamic> practiceItem({
  int id = 1,
  int category = 1,
  String quality = '美育',
  double score = 1.5,
  bool approved = true,
  bool deleted = false,
  String name = '示例实践项目',
}) =>
    {
      'id': id,
      'jd': score,
      'sfsc': deleted,
      'cyrshzt': {
        'value': approved ? 5 : 3,
        'label': approved ? '审核通过' : '审核中'
      },
      'hdsj': '2026-09-20T08:00:00+08:00',
      'xm': {
        'mc': name,
        'zxfs': 50,
        'zdfs': 100,
        'xmfl': {
          'id': category,
          'mc': ['第二课堂', '第三课堂', '第四课堂'][category - 1]
        },
        'xmlb': {'mc': '志愿服务'},
        'xmlx': {'mc': quality},
      },
      'hdjjygrcdgz': '项目成员',
      'qksm': '示例说明',
    };

PracticeDetails practiceSnapshot({DateTime? date}) => PracticeDetails(
      updatedAt: date ?? DateTime.now(),
      items: [
        PracticeScoreItem.fromSztzJson(practiceItem()),
        PracticeScoreItem.fromSztzJson(
            practiceItem(id: 2, quality: '社会责任', score: 2)),
        PracticeScoreItem.fromSztzJson(practiceItem(id: 3, category: 2)),
        PracticeScoreItem.fromSztzJson(practiceItem(id: 4, category: 3)),
      ],
    );

class PracticeMemoryDb extends Fake implements DatabaseHelper {
  final pages = <String, String>{};
  @override
  String? getCachedWebPage(String key) => pages[key];
  @override
  Future<void> setCachedWebPage(String key, String value) async =>
      pages[key] = value;
  @override
  Future<void> removeAllCachedWebPage() async => pages.clear();
  @override
  Future<void> removeScholar() async {}
}

class PracticeTestScholar extends Scholar {
  PracticeTestScholar({PracticeDetails? cached})
      : cache = cached ?? const PracticeDetails() {
    username = '3200000000';
    password = '';
    isLogan = true;
    pt2 = 6.5;
    pt3 = 2;
    pt4 = 1;
  }
  PracticeDetails cache;
  int requests = 0;
  Future<PracticeDetails> Function()? response;
  @override
  PracticeDetails get cachedPracticeDetails => cache;
  @override
  Future<PracticeDetails> getPracticeDetails() async {
    requests++;
    final result = await (response?.call() ?? Future.value(practiceSnapshot()));
    if (result.error == null) cache = result;
    return result;
  }
}

class PracticeHttpClient extends Fake implements HttpClient {
  PracticeHttpClient(List<PracticeResponse> responses)
      : responses = Queue.of(responses);
  final Queue<PracticeResponse> responses;
  final requests = <PracticeRequest>[];
  Future<HttpClientRequest> _open(Uri uri) async {
    final request = PracticeRequest(uri, responses.removeFirst());
    requests.add(request);
    return request;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri uri) => _open(uri);
  @override
  Future<HttpClientRequest> postUrl(Uri uri) => _open(uri);
}

class PracticeRequest extends Fake implements HttpClientRequest {
  PracticeRequest(this.uri, this.response);
  @override
  final Uri uri;
  final PracticeResponse response;
  @override
  final headers = PracticeHeaders({});
  @override
  final cookies = <Cookie>[];
  @override
  bool followRedirects = true;
  @override
  int contentLength = 0;
  @override
  Future<HttpClientResponse> close() async {
    await response.gate?.future;
    return response;
  }
}

class PracticeHeaders extends Fake implements HttpHeaders {
  PracticeHeaders(this.values);
  final Map<String, String> values;
  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = value.toString();
}

class PracticeResponse extends Stream<List<int>> implements HttpClientResponse {
  PracticeResponse(String text,
      {this.statusCode = 200,
      Map<String, String> headers = const {},
      this.cookies = const [],
      this.gate})
      : body = utf8.encode(text),
        headers = PracticeHeaders(Map.of(headers));
  final List<int> body;
  final Completer<void>? gate;
  @override
  final int statusCode;
  @override
  final PracticeHeaders headers;
  @override
  final List<Cookie> cookies;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream.value(body).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<PracticeResponse> practiceLogin({bool anonymous = false}) => [
      PracticeResponse('', statusCode: 302, headers: {
        'location': 'https://sztz.zju.edu.cn/dekt/?ticket=mock-ticket',
      }),
      PracticeResponse('',
          cookies: [Cookie('SESSION', 'mock-session')..path = '/dekt']),
      PracticeResponse(jsonEncode({
        'success': true,
        'code': 0,
        'data': base64Encode(utf8.encode(jsonEncode({
          'anonymous': anonymous,
          'userId': 'mock-user',
          'roles': ['STUDENT_ROLE'],
        }))),
      })),
    ];

PracticeResponse practiceResponse(List<Object?> items,
        {Completer<void>? gate, int pages = 1}) =>
    PracticeResponse(
        jsonEncode(
            {'success': true, 'code': 0, 'data': items, 'totalPages': pages}),
        gate: gate);
