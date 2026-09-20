import 'dart:async';
import 'dart:io';

import 'package:litechron/http/spider.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/semester.dart';
import 'package:litechron/page/option/option_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'support/refresh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.testMode = true;
    Get.put<OptionController>(RefreshOptionController(),
        tag: 'optionController');
  });
  tearDown(() => Get.reset());

  test('未登录时不创建 Spider', () async {
    var factoryCalled = false;
    final scholar = Scholar(spiderFactory: (_, __) {
      factoryCalled = true;
      return ControlledSpider();
    });
    expect(await scholar.refresh(userInitiated: true), ['未登录']);
    expect(factoryCalled, isFalse);
  });

  test('会话初始化期间下拉，共享成功结果且仅抓取一轮', () async {
    final fixture = RefreshFixture();
    final login = Completer<List<String?>>();
    fixture.spider.loginGate = login;
    final statuses = <List<ModuleFetchStatus>>[];

    final automatic = fixture.scholar.refresh();
    final manual = fixture.scholar
        .refresh(userInitiated: true, onFetchStatus: statuses.add);

    expect(manual, same(automatic));
    expect(fixture.factoryCalls, 1);
    expect(fixture.spider.loginCalls, 1);
    expect(fixture.spider.fetches, isEmpty);
    expect(statuses.single.map((s) => s.state),
        everyElement(FetchModuleState.pending));

    login.complete([null]);
    final fetch = await fixture.spider.fetchAt(0);
    fetch.result.complete(fetchResult());
    final result = await automatic;
    expect(await manual, same(result));
    expect(result, everyElement(isNull));
    expect(fixture.spider.interactionRequests, [false]);
    expect(fixture.db.savedGradeTimes, hasLength(1));
    expect(statuses.last.map((s) => s.state),
        everyElement(FetchModuleState.success));
  });

  test('仅有自动调用时共享真实错误，不追加补刷', () async {
    final fixture = RefreshFixture();
    final first = fixture.scholar.refresh();
    final second = fixture.scholar.refresh();
    final fetch = await fixture.spider.fetchAt(0);
    fetch.result.complete(fetchResult(errors: academicErrors));

    expect(await first, academicErrors);
    expect(await second, same(await first));
    expect(fixture.spider.interactionRequests, [false]);
    expect(fixture.scholar.lastUpdateTimeGrade, oldUpdateTime);
    expect(fixture.scholar.lastUpdateTimeCourse, oldUpdateTime);
    expect(
        fixture.scholar.lastUpdateTimeHomework.isAfter(oldUpdateTime), isTrue);
  });

  test('成绩课表失败而作业成功，多次下拉共同等待一次完整手动补刷', () async {
    final fixture = RefreshFixture();
    final scholar = fixture.scholar;
    final oldGrades = scholar.grades;
    final oldSemesters = scholar.semesters;
    final newGrade = sampleGrade(updated: true);
    final newSemester = Semester('2025-2026秋冬');
    final firstTodo = sampleTodo('first');
    final secondTodo = sampleTodo('second');
    final statuses = <List<ModuleFetchStatus>>[];
    var completed = false;

    final automatic = scholar.refresh();
    unawaited(automatic.then((_) => completed = true));
    final firstFetch = await fixture.spider.fetchAt(0);
    final manual =
        scholar.refresh(userInitiated: true, onFetchStatus: statuses.add);
    final anotherManual = scholar.refresh(userInitiated: true);
    firstFetch.result.complete(fetchResult(
        errors: academicErrors,
        grades: [newGrade],
        semesters: [newSemester],
        todos: [firstTodo]));
    final retry = await fixture.spider.fetchAt(1);

    expect(scholar.grades, same(oldGrades));
    expect(scholar.semesters, same(oldSemesters));
    expect(scholar.todos.single, same(firstTodo));
    expect(fixture.db.savedGradeTimes, [oldUpdateTime]);
    expect(fixture.db.savedCourseTimes, [oldUpdateTime]);
    expect(fixture.db.savedHomeworkTimes.single.isAfter(oldUpdateTime), isTrue);
    expect(completed, isFalse);
    expect(statuses.last.map((s) => s.state),
        everyElement(FetchModuleState.pending));

    final duringRetry = scholar.refresh(userInitiated: true);
    for (final future in [manual, anotherManual, duringRetry]) {
      expect(future, same(automatic));
    }
    // 第一轮迟到的进度不能覆盖补刷的状态和数据。
    firstFetch.emit(fetchResult(todos: [sampleTodo('stale')]));
    expect(statuses.last.map((s) => s.state),
        everyElement(FetchModuleState.pending));

    retry.result.complete(fetchResult(
        grades: [newGrade], semesters: [newSemester], todos: [secondTodo]));
    final results =
        await Future.wait([automatic, manual, anotherManual, duringRetry]);
    expect(results, everyElement(everyElement(isNull)));
    expect(fixture.spider.interactionRequests, [false, true]);
    expect(scholar.grades['TEST0001']!.single, same(newGrade));
    expect(scholar.semesters.single, same(newSemester));
    expect(scholar.todos.single, same(secondTodo));
    expect(scholar.lastUpdateTimeGrade.isAfter(oldUpdateTime), isTrue);
    expect(scholar.lastUpdateTimeCourse.isAfter(oldUpdateTime), isTrue);
    expect(scholar.gpa.first, 4.5);
    expect(scholar.credit, 2.0);
    expect(fixture.db.savedGradeTimes, hasLength(2));
  });

  test('补刷仍失败则向所有调用者返回实际错误，失败板块缓存和时间不变', () async {
    final fixture = RefreshFixture();
    final scholar = fixture.scholar;
    final oldGrades = scholar.grades;
    final oldSemesters = scholar.semesters;
    final automatic = scholar.refresh();
    final manual = scholar.refresh(userInitiated: true);
    (await fixture.spider.fetchAt(0))
        .result
        .complete(fetchResult(errors: academicErrors));
    final retry = await fixture.spider.fetchAt(1);
    final moreCalls =
        List.generate(5, (_) => scholar.refresh(userInitiated: true));
    const retryErrors = <String?>[
      null,
      '课表查询出错：验证码未填写',
      null,
      '成绩查询出错：网络错误',
      null,
      null,
      null,
    ];
    retry.result.complete(
        fetchResult(errors: retryErrors, todos: [sampleTodo('retry')]));

    final results = await Future.wait([automatic, manual, ...moreCalls]);
    for (final result in results) {
      expect(result, retryErrors);
      expect(result, same(results.first));
    }
    expect(fixture.spider.interactionRequests, [false, true]);
    expect(scholar.grades, same(oldGrades));
    expect(scholar.semesters, same(oldSemesters));
    expect(scholar.lastUpdateTimeGrade, oldUpdateTime);
    expect(scholar.lastUpdateTimeCourse, oldUpdateTime);
    expect(scholar.todos.single.id, 'retry');
    expect(fixture.db.savedGradeTimes, [oldUpdateTime, oldUpdateTime]);
    expect(fixture.db.savedCourseTimes, [oldUpdateTime, oldUpdateTime]);
  });

  test('手动发起的刷新允许交互，失败后不再追加一轮', () async {
    final fixture = RefreshFixture();
    final manual = fixture.scholar.refresh(userInitiated: true);
    final anotherManual = fixture.scholar.refresh(userInitiated: true);
    final automatic = fixture.scholar.refresh();
    (await fixture.spider.fetchAt(0))
        .result
        .complete(fetchResult(errors: academicErrors));
    for (final result
        in await Future.wait([manual, anotherManual, automatic])) {
      expect(result, academicErrors);
    }
    expect(fixture.spider.interactionRequests, [true]);
  });

  test('后加入的页面立即收到当前进度和可用的异步数据', () async {
    final fixture = RefreshFixture();
    fixture.db.asyncRefresh = true;
    final automatic = fixture.scholar.refresh();
    final fetch = await fixture.spider.fetchAt(0);
    final partial = fetchResult(errors: [
      for (final label in fetchLabels) label == '作业' ? null : '$label查询进行中'
    ], todos: [
      sampleTodo('partial')
    ]);
    fetch.emit(partial);
    expect(fixture.scholar.todos.single.id, 'cached');
    expect(fixture.scholar.lastUpdateTimeHomework, oldUpdateTime);

    var partialUpdates = 0;
    final statuses = <List<ModuleFetchStatus>>[];
    final manual = fixture.scholar.refresh(
        userInitiated: true,
        onPartialUpdate: () => partialUpdates++,
        onFetchStatus: statuses.add);
    expect(partialUpdates, 1);
    expect(fixture.scholar.todos.single.id, 'partial');
    expect(
        fixture.scholar.lastUpdateTimeHomework.isAfter(oldUpdateTime), isTrue);
    expect(fixture.scholar.lastUpdateTimeGrade, oldUpdateTime);
    expect(statuses.single[5].state, FetchModuleState.success);
    expect(statuses.single[1].state, FetchModuleState.pending);

    var laterUpdates = 0;
    final later =
        fixture.scholar.refresh(onPartialUpdate: () => laterUpdates++);
    expect(laterUpdates, 1);
    fetch.emit(partial);
    expect(partialUpdates, 2);
    expect(laterUpdates, 2);
    fetch.result.complete(fetchResult(todos: [sampleTodo('final')]));
    await Future.wait([automatic, manual, later]);
    expect(fixture.spider.interactionRequests, [false]);
    expect(fixture.db.savedHomeworkTimes, hasLength(1));
  });

  for (final asyncRefresh in [false, true]) {
    test('异步刷新开关为 $asyncRefresh：进度照常发送，按开关合并数据和时间', () async {
      final fixture = RefreshFixture();
      fixture.db.asyncRefresh = asyncRefresh;
      fixture.scholar
        ..isPracticeScoresGet = true
        ..pt2 = 1.0
        ..pt3 = 2.0
        ..pt4 = 3.0;
      var updates = 0;
      final statuses = <List<ModuleFetchStatus>>[];
      final future = fixture.scholar.refresh(
          onPartialUpdate: () => updates++, onFetchStatus: statuses.add);
      final fetch = await fixture.spider.fetchAt(0);
      final todo = sampleTodo('partial');
      fetch.emit(fetchResult(errors: [
        for (final label in fetchLabels) label == '作业' ? null : '$label查询进行中'
      ], todos: [
        todo
      ]));

      expect(updates, asyncRefresh ? 1 : 0);
      expect(
          fixture.scholar.todos.single.id, asyncRefresh ? 'partial' : 'cached');
      expect(fixture.scholar.lastUpdateTimeHomework.isAfter(oldUpdateTime),
          asyncRefresh);
      expect(fixture.scholar.lastUpdateTimeGrade, oldUpdateTime);
      expect(fixture.scholar.lastUpdateTimeCourse, oldUpdateTime);
      expect(fixture.scholar.isPracticeScoresGet, isTrue);
      expect([fixture.scholar.pt2, fixture.scholar.pt3, fixture.scholar.pt4],
          [1.0, 2.0, 3.0]);
      expect(statuses.last[5].state, FetchModuleState.success);
      expect(fixture.db.savedHomeworkTimes, isEmpty);

      fetch.result.complete(fetchResult(todos: [todo]));
      expect(await future, everyElement(isNull));
      expect(fixture.scholar.todos.single, same(todo));
      expect(fixture.scholar.lastUpdateTimeHomework.isAfter(oldUpdateTime),
          isTrue);
      expect(fixture.db.savedHomeworkTimes, hasLength(1));
    });
  }

  test('抓取异常结束后可正常再刷新，并向并发调用返回同一错误', () async {
    final fixture = RefreshFixture();
    final statuses = <List<ModuleFetchStatus>>[];
    final automatic = fixture.scholar.refresh(onFetchStatus: statuses.add);
    final concurrent = fixture.scholar.refresh();
    (await fixture.spider.fetchAt(0))
        .result
        .completeError(const SocketException('offline'));
    expect(await automatic, ['网络连接失败，请检查网络后重试']);
    expect(await concurrent, same(await automatic));
    expect(statuses.last.map((s) => s.state),
        everyElement(FetchModuleState.failed));

    final next = fixture.scholar.refresh(userInitiated: true);
    (await fixture.spider.fetchAt(1)).result.complete(fetchResult());
    expect(await next, everyElement(isNull));
    expect(fixture.spider.interactionRequests, [false, true]);
  });

  test('初始化异常也纳入手动补刷，原任务不会提前完成', () async {
    final fixture = RefreshFixture();
    final login = Completer<List<String?>>();
    fixture.spider.loginGate = login;
    final automatic = fixture.scholar.refresh();
    final manual = fixture.scholar.refresh(userInitiated: true);
    login.completeError(const SocketException('offline'));
    final retry = await fixture.spider.fetchAt(0);
    expect(fixture.spider.interactionRequests, [false, true]);
    expect(fixture.spider.loginCalls, 2);
    retry.result.complete(fetchResult());
    expect(await automatic, everyElement(isNull));
    expect(await manual, same(await automatic));
  });

  test('登录失败返回登录错误并保留时间，下次刷新仍可初始化会话', () async {
    final fixture = RefreshFixture();
    final login = Completer<List<String?>>();
    fixture.spider.loginGate = login;
    final failed = fixture.scholar.refresh();
    login.complete(['无法登录教务网']);
    expect(await failed, ['无法登录教务网']);
    expect(fixture.scholar.lastUpdateTimeGrade, oldUpdateTime);
    expect(fixture.scholar.lastUpdateTimeCourse, oldUpdateTime);
    expect(fixture.scholar.lastUpdateTimeHomework, oldUpdateTime);
    final next = fixture.scholar.refresh(userInitiated: true);
    (await fixture.spider.fetchAt(0)).result.complete(fetchResult());
    expect(await next, everyElement(isNull));
    expect(fixture.spider.loginCalls, 2);
  });

  test('页面回调异常不影响其他订阅者，结束后不再接收旧任务进度', () async {
    final fixture = RefreshFixture();
    fixture.db.asyncRefresh = true;
    final broken = fixture.scholar.refresh(
        onPartialUpdate: () => throw StateError('disposed listener'),
        onFetchStatus: (_) => throw StateError('disposed listener'));
    final fetch = await fixture.spider.fetchAt(0);
    var updates = 0;
    final statuses = <List<ModuleFetchStatus>>[];
    final healthy = fixture.scholar
        .refresh(onPartialUpdate: () => updates++, onFetchStatus: statuses.add);
    fetch.emit(fetchResult(todos: [sampleTodo('partial')]));
    expect(updates, 1);
    expect(statuses, hasLength(2));
    fetch.result.complete(fetchResult());
    await Future.wait([broken, healthy]);
    final statusCount = statuses.length;

    final next = fixture.scholar.refresh(userInitiated: true);
    final nextFetch = await fixture.spider.fetchAt(1);
    fetch.emit(fetchResult(todos: [sampleTodo('stale')]));
    expect(statuses, hasLength(statusCount));
    expect(updates, 1);
    expect(fixture.scholar.todos.single.id, 'partial');
    nextFetch.result.complete(fetchResult());
    expect(await next, everyElement(isNull));
  });

  test('落盘完成前加入的下拉仍等待同一任务', () async {
    final fixture = RefreshFixture();
    final saving = Completer<void>();
    final releaseSave = Completer<void>();
    fixture.db.onSave = () {
      saving.complete();
      return releaseSave.future;
    };
    var completed = false;
    final automatic = fixture.scholar.refresh();
    unawaited(automatic.then((_) => completed = true));
    (await fixture.spider.fetchAt(0)).result.complete(fetchResult());
    await saving.future;
    final manual = fixture.scholar.refresh(userInitiated: true);
    expect(manual, same(automatic));
    expect(completed, isFalse);
    releaseSave.complete();
    await Future.wait([automatic, manual]);
    expect(fixture.spider.interactionRequests, [false]);
  });
}
