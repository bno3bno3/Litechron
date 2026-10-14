import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:litechron/http/zjuServices/sztz.dart';
import 'package:litechron/http/zjuServices/exceptions.dart';
import 'package:litechron/model/practice_details.dart';
import 'package:litechron/model/practice_score_item.dart';
import 'package:litechron/model/scholar.dart';

import 'support/practice_fakes.dart';

void main() {
  Future<Cookie?> sso(bool fresh) async =>
      Cookie('iPlanetDirectoryPro', 'mock-sso');

  test('一轮请求获取三类、使用个人 jd，并仅缓存展示字段', () async {
    final db = PracticeMemoryDb();
    final client = PracticeHttpClient([
      ...practiceLogin(),
      practiceResponse([
        {...practiceItem(), 'privateStudentName': 'should-not-persist'},
        practiceItem(id: 2, category: 2),
        practiceItem(id: 3, category: 3),
      ]),
    ]);
    final service = Sztz(account: '3200000000', db: db);
    expect(Sztz.readCache(db, '3200000000').hasCache, isFalse);
    expect(client.requests, isEmpty);
    final result = await service.getPracticeDetails(client, sso);
    expect(result.error, isNull);
    expect(result.items.map((item) => item.categoryId), [1, 2, 3]);
    expect(result.items.first.score, 1.5);
    expect(client.requests, hasLength(4));
    expect(
        client.requests.any((request) => request.uri.host == 'zdbk.zju.edu.cn'),
        isFalse);
    expect(client.requests[2].cookies.any((cookie) => cookie.name == 'SESSION'),
        isTrue);
    final raw = db.pages.values.single;
    expect(raw, isNot(contains('should-not-persist')));
    expect(raw, isNot(contains('mock-sso')));
    expect(raw, isNot(contains('mock-session')));
    expect(Sztz.readCache(db, '3200000000').items, hasLength(3));
    expect(Sztz.readCache(db, 'another-mock-account').hasCache, isFalse);
  });

  test('成功空列表也是缓存，后续请求复用业务登录态', () async {
    final db = PracticeMemoryDb();
    final client = PracticeHttpClient(
        [...practiceLogin(), practiceResponse([]), practiceResponse([])]);
    final service = Sztz(account: '3200000000', db: db);
    expect((await service.getPracticeDetails(client, sso)).hasCache, isTrue);
    expect(Sztz.readCache(db, '3200000000').items, isEmpty);
    await service.getPracticeDetails(client, sso);
    expect(client.requests, hasLength(5));
  });

  test('并发刷新只获取一轮明细', () async {
    final gate = Completer<void>();
    final client = PracticeHttpClient([
      ...practiceLogin(),
      practiceResponse([practiceItem()], gate: gate)
    ]);
    final service = Sztz(account: '3200000000');
    final first = service.getPracticeDetails(client, sso);
    final second = service.getPracticeDetails(client, sso);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(identical(results.first, results.last), isTrue);
    expect(client.requests, hasLength(4));
  });

  test('请求失败保留缓存、时间和具体原因', () async {
    final db = PracticeMemoryDb();
    final client = PracticeHttpClient([
      ...practiceLogin(),
      practiceResponse([practiceItem()]),
      PracticeResponse('private response body', statusCode: 503),
    ]);
    final service = Sztz(account: '3200000000', db: db);
    final first = await service.getPracticeDetails(client, sso);
    final saved = db.pages.values.single;
    final failure = await service.getPracticeDetails(client, sso);
    expect(failure.error, '实践明细获取失败：服务器返回 HTTP 503');
    expect(failure.updatedAt, first.updatedAt);
    expect(failure.items, hasLength(1));
    expect(db.pages.values.single, saved);
  });

  test('格式异常不覆盖旧缓存或报成成功空列表', () async {
    final db = PracticeMemoryDb();
    final client = PracticeHttpClient([
      ...practiceLogin(),
      practiceResponse([practiceItem()]),
      PracticeResponse('{not-json'),
    ]);
    final service = Sztz(account: '3200000000', db: db);
    final first = await service.getPracticeDetails(client, sso);
    final result = await service.getPracticeDetails(client, sso);
    expect(result.error, '实践明细读取失败：返回的数据格式异常');
    expect(result.updatedAt, first.updatedAt);
    expect(result.items, hasLength(1));
  });

  test('匿名业务身份最多重新认证一次，不接受 HTTP 200 为登录成功', () async {
    final client = PracticeHttpClient([
      ...practiceLogin(anonymous: true),
      ...practiceLogin(anonymous: true),
    ]);
    final freshness = <bool>[];
    final result =
        await Sztz(account: '3200000000').getPracticeDetails(client, (fresh) {
      freshness.add(fresh);
      return sso(fresh);
    });
    expect(freshness, [false, true]);
    expect(result.error, '素质拓展登录失败：登录状态已过期');
    expect(client.requests.any((r) => r.uri.path.endsWith('getSqjl')), isFalse);
  });

  test('统一认证的网络与超时原因保留，非有限分数不会写坏缓存', () async {
    for (final reason in ['网络错误', '请求超时']) {
      final result = await Sztz(account: '3200000000').getPracticeDetails(
          PracticeHttpClient([]),
          (_) async => throw ExceptionWithMessage(reason));
      expect(result.error,
          reason == '网络错误' ? '素质拓展登录失败：无法连接服务器' : '素质拓展登录失败：请求超时');
    }
    final item =
        PracticeScoreItem.fromSztzJson({...practiceItem(), 'jd': 'NaN'});
    expect(item.countsTowardTotal, isFalse);
    expect(item.score, -1);
  });

  test('登出后的迟到结果不写缓存', () async {
    final gate = Completer<void>();
    final db = PracticeMemoryDb();
    final client = PracticeHttpClient([
      ...practiceLogin(),
      practiceResponse([practiceItem()], gate: gate)
    ]);
    final service = Sztz(account: '3200000000', db: db);
    final result = service.getPracticeDetails(client, sso);
    while (client.requests.length < 4) {
      await Future<void>.delayed(Duration.zero);
    }
    service.logout();
    gate.complete();
    expect((await result).hasCache, isFalse);
    expect(db.pages, isEmpty);
  });

  test('美育与其他只按分类汇总审核通过项目，项目名称不影响分类', () {
    final details = PracticeDetails(
        updatedAt: DateTime.now(),
        items: PracticeScoreItem.parseSztzItems([
          practiceItem(),
          practiceItem(id: 2, quality: '社会责任', score: 2, name: '美育字样的项目'),
          practiceItem(id: 3, approved: false, score: 20),
          practiceItem(id: 4, deleted: true, score: 10),
          practiceItem(id: 5, category: 2, score: 30),
          practiceItem(),
        ]));
    expect(details.subtotal(PracticeFilter.aesthetic), 1.5);
    expect(details.subtotal(PracticeFilter.other), 2);
    expect(details.records(1, PracticeFilter.aesthetic), hasLength(2));
    expect(details.records(1, PracticeFilter.other).single.id, 2);
  });

  test('分类缺失或接口多页时不伪造合计分数', () async {
    final unknown = PracticeDetails(updatedAt: DateTime.now(), items: [
      PracticeScoreItem.fromSztzJson(practiceItem(quality: '')),
    ]);
    expect(unknown.subtotal(PracticeFilter.other), isNull);
    final client = PracticeHttpClient([
      ...practiceLogin(),
      practiceResponse([practiceItem()], pages: 2)
    ]);
    final result =
        await Sztz(account: '3200000000').getPracticeDetails(client, sso);
    expect(result.complete, isFalse);
    expect(result.subtotal(PracticeFilter.aesthetic), isNull);
    expect(result.items, hasLength(1));
  });

  test('MockSpider明细不会登录真实服务，正常读取保留总分', () async {
    final db = PracticeMemoryDb();
    final scholar = Scholar()
      ..username = '3200000000'
      ..password = ''
      ..isLogan = true
      ..pt2 = 6.5
      ..db = db;
    expect(scholar.cachedPracticeDetails.hasCache, isFalse);
    final details = await scholar.getPracticeDetails();
    expect(details.hasCache, isTrue);
    expect(scholar.pt2, 6.5);
    expect(scholar.cachedPracticeDetails.hasCache, isTrue);
  });
}
