import 'dart:async';

import 'package:get/get.dart';

import 'package:litechron/page/option/option_controller.dart';

import 'period.dart';
import 'grade.dart';
import 'recommend_gpa_rule.dart';
import 'semester.dart';
import 'todo.dart';
import 'package:litechron/utils/gpa_helper.dart';
import 'package:litechron/http/spider.dart';
import 'package:litechron/http/ugrs_spider.dart';
import 'package:litechron/http/grs_spider.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/worker/refresh_lock.dart';

typedef SpiderFactory = Spider Function(String username, String password);

class Scholar {
  Scholar({SpiderFactory? spiderFactory})
      : _spiderFactory = spiderFactory ?? _createSpider;

  // 构造用户对象
  DatabaseHelper? _db;

  set db(DatabaseHelper? db) {
    _db = db;
  }

  // 登录状态
  bool isLogan = false;

  /// 运行在后台任务 isolate 中：不参与前台锁，互斥由后台入口自行处理
  bool runsInBackground = false;
  DateTime lastUpdateTimeGrade = DateTime.parse("20010101");
  DateTime lastUpdateTimeCourse = DateTime.parse("20010101");
  DateTime lastUpdateTimeHomework = DateTime.parse("20010101");

  // 爬虫区
  String? username;
  String? password;
  Spider? _spider;
  final SpiderFactory _spiderFactory;

  static Spider _createSpider(String username, String password) {
    if (username == '3200000000') return MockSpider();
    return username.startsWith('3')
        ? UgrsSpider(username, password)
        : GrsSpider(username, password);
  }

  bool get isGrs => !username!.startsWith('3');

  // 按学期整理好的学业信息，包括该学期的所有科目、考试、课表、均绩等
  List<Semester> semesters = <Semester>[];

  // 按课程号整理好的成绩单（方便算重修成绩）
  Map<String, List<Grade>> grades = {};

  // 保研 GPA, 四个数据依次为五分制、四分制（4.3 分制）、原始的四分制、百分制
  List<double> gpa = [0.0, 0.0, 0.0, 0.0];

  // 出国 GPA, 四个数据依次为五分制、四分制（4.3 分制）、原始的四分制、百分制
  List<double> aboardGpa = [0.0, 0.0, 0.0, 0.0];

  // 所获学分
  double credit = 0.0;

  // 主修成绩，两个数据依次为主修GPA，主修学分（官网口径）
  List<double> majorGpaAndCredit = [0.0, 0.0];

  // 以下为派生值，不持久化：加载、刷新和用户改动设置时由 recalculateDerivedGpa 重算
  // 按「主修课程来源」得到的主修GPA与主修学分：官网口径时等于 majorGpaAndCredit
  List<double> effectiveMajorGpaAndCredit = [0.0, 0.0];
  // 五分制推免绩点，两个数据依次为重修取首次、取最高
  List<double> recommendGpa = [0.0, 0.0];
  bool _useCustomMajor = false;
  Map<String, bool> _majorOverrides = const {};

  /// 一门课是否计入主修：自定义模式下覆盖表优先，无记录跟随官网标记
  bool isMajor(Grade grade) => _useCustomMajor
      ? (_majorOverrides[grade.id] ?? grade.major)
      : grade.major;

  // 特殊日期
  Map<DateTime, String> specialDates = {};

  // 作业（学在浙大）
  List<Todo> todos = [];

  // 实践学分（素质拓展）
  double pt2 = 0.0; // 二课分
  double pt3 = 0.0; // 三课分
  double pt4 = 0.0; // 四课分
  bool isPracticeScoresGet = false; // 是否成功获取到二三四课堂分数

  int get gradedCourseCount {
    return grades.values.fold(0, (p, e) => p + e.length);
  }

  List<Period> get periods {
    return semesters.fold(<Period>[], (p, e) => p + e.periods);
  }

  Semester get thisSemester {
    if (semesters.length > 1) {
      // 只有成绩、没有课表和考试的学期 periods 为空，直接取 .last 会抛异常
      var prevSemesterPeriods = semesters[1].periods;
      if (prevSemesterPeriods.isNotEmpty &&
          prevSemesterPeriods.last.endTime
              .isAfter(DateTime.now().subtract(const Duration(days: 14)))) {
        return semesters[1];
      } else {
        return semesters[0];
      }
    } else {
      return semesters.isEmpty ? Semester('未刷新') : semesters.first;
    }
  }

  bool get isNearExamWeek {
    var thisSem = thisSemester;
    for (var exam in thisSem.exams) {
      var now = DateTime.now();
      if (now.isAfter(exam.time[0].subtract(const Duration(days: 3))) &&
          now.isBefore(exam.time[0].add(const Duration(days: 3)))) {
        return true;
      }
    }
    return false;
  }

  // 初始化以获取Cookies，并刷新数据
  Future<List<String?>> login() async {
    if (username == null || password == null) {
      return ["未登录"];
    }
    _spider = _spiderFactory(username!, password!);
    var loginErrorMessage = await _spider!.login();
    if (loginErrorMessage.every((e) => e == null)) {
      isLogan = true;
      _db?.setScholar(this);
    }
    return loginErrorMessage;
  }

  Future<bool> logout() async {
    username = "";
    password = "";
    semesters = [];
    grades = {};
    gpa = [0.0, 0.0, 0.0, 0.0];
    aboardGpa = [0.0, 0.0, 0.0, 0.0];
    credit = 0.0;
    majorGpaAndCredit = [0.0, 0.0];
    effectiveMajorGpaAndCredit = [0.0, 0.0];
    recommendGpa = [0.0, 0.0];
    pt2 = 0.0;
    pt3 = 0.0;
    pt4 = 0.0;
    isPracticeScoresGet = false;
    isLogan = false;
    lastUpdateTimeGrade = DateTime.parse("20010101");
    lastUpdateTimeCourse = DateTime.parse("20010101");
    lastUpdateTimeHomework = DateTime.parse("20010101");
    _spider?.logout();
    await _db?.removeScholar();
    await _db?.removeAllCachedWebPage();
    return true;
  }

  // 登录、抓取和必要的手动补刷共用一个任务，后来者订阅进度并等待同一结果。
  _ScholarRefreshTask? _refreshTask;

  Future<List<String?>> refresh(
      {bool userInitiated = false,
      void Function()? onPartialUpdate,
      void Function(List<ModuleFetchStatus> statuses)? onFetchStatus}) {
    if (!isLogan) {
      return Future.value(["未登录"]);
    }

    final current = _refreshTask;
    final task = current ?? _ScholarRefreshTask(userInitiated);
    _refreshTask = task;
    if (userInitiated) task.manualRefreshRequested = true;
    _subscribeToRefresh(task, onPartialUpdate, onFetchStatus);
    if (current == null) {
      unawaited(_runRefresh(task));
    }
    return task.completer.future;
  }

  void _subscribeToRefresh(
      _ScholarRefreshTask task,
      void Function()? onPartialUpdate,
      void Function(List<ModuleFetchStatus>)? onFetchStatus) {
    if (onPartialUpdate != null) {
      task.partialUpdateListeners.add(onPartialUpdate);
      if (task.latestPartial != null && task.asyncRefresh) {
        if (task.partialApplied) {
          _notifyRefreshListener(onPartialUpdate);
        } else {
          _applyPartialRefresh(task);
        }
      }
    }
    if (onFetchStatus != null) {
      task.statusListeners.add(onFetchStatus);
      if (task.statuses.isNotEmpty) {
        _notifyRefreshListener(() => onFetchStatus(task.statuses));
      }
    }
  }

  Future<void> _runRefresh(_ScholarRefreshTask task) async {
    // 后台任务正在登录教务网时先等它结束，否则双方会互相顶掉会话。
    // 前台是用户在等，最多等一小段时间，超时就照常刷新。
    final useLock = RefreshLock.enabled && !runsInBackground;
    if (useLock) {
      await RefreshLock.waitUntilFree(RefreshLock.backgroundKey);
      await RefreshLock.acquire(RefreshLock.foregroundKey);
    }
    try {
      var errors = await _refreshOnce(task, userInitiated: task.startedByUser);
      // 手动下拉加入自动任务后，仅在自动任务失败时追加一轮完整刷新。
      // 不循环重试，补刷期间再加入的调用也只等待这一轮。
      if (!task.startedByUser &&
          task.manualRefreshRequested &&
          errors.any((e) => e != null)) {
        errors = await _refreshOnce(task, userInitiated: true);
      }
      task.completer.complete(errors);
    } catch (_) {
      task.completer.complete(['网络连接失败，请检查网络后重试']);
    } finally {
      if (useLock) {
        await RefreshLock.release(RefreshLock.foregroundKey);
      }
      _refreshTask = null;
      task.partialUpdateListeners.clear();
      task.statusListeners.clear();
      task.latestPartial = null;
    }
  }

  Future<List<String?>> _refreshOnce(_ScholarRefreshTask task,
      {required bool userInitiated}) async {
    final round = ++task.round;
    task.latestPartial = null;
    task.partialApplied = false;
    try {
      if (username == null || password == null) return ['未登录'];
      // getEverything 会在会话未初始化或过期时登录；创建 Spider 也在共享
      // 任务内完成，避免启动时先 login 再 refresh 留下并发空隙。
      final spider = _spider ??= _spiderFactory(username!, password!);
      task.asyncRefresh = _db?.getAsyncRefresh() ?? false;
      final fetchLabels = spider.fetchLabels;
      _publishFetchStatuses(task, [
        for (final label in fetchLabels)
          ModuleFetchStatus(label, FetchModuleState.pending)
      ]);

      final value = await spider.getEverything(
          allowUserInteraction: userInitiated,
          // 即使当前没有页面订阅也记录进度，后来者可以立即收到当前状态。
          // 仅开启异步刷新且有数据订阅者时才合并中间态；后台仍只合并终态。
          onProgress: (partial) {
            if (!identical(_refreshTask, task) || task.round != round) return;
            task.latestPartial = partial;
            task.partialApplied = false;
            _applyPartialRefresh(task);
            _publishFetchStatuses(
                task, moduleStatusesFromErrors(partial.item2, fetchLabels));
          });

      _applyFetchResult(value);
      if (value.item1.every((e) => e == null)) {
        updateLastUpdateTime(value.item2);
      }
      task.latestPartial = null;
      // 最后完成的模块不触发 onProgress，在这里上报本轮终态。
      _publishFetchStatuses(
          task, moduleStatusesFromErrors(value.item2, fetchLabels));
      await _db?.setScholar(this);
      return value.item1.every((e) => e == null) ? value.item2 : value.item1;
    } catch (_) {
      // 异常也结束本轮状态并返回真实失败，已有数据保留；共享任务仍可补刷。
      _publishFetchStatuses(task, [
        for (final status in task.statuses)
          ModuleFetchStatus(
              status.label,
              status.state == FetchModuleState.pending
                  ? FetchModuleState.failed
                  : status.state)
      ]);
      return ['网络连接失败，请检查网络后重试'];
    }
  }

  void _applyPartialRefresh(_ScholarRefreshTask task) {
    final partial = task.latestPartial;
    if (partial == null ||
        task.partialApplied ||
        task.partialUpdateListeners.isEmpty ||
        !task.asyncRefresh) {
      return;
    }
    try {
      _applyFetchResult(partial, partial: true);
      if (partial.item1.every((e) => e == null)) {
        updateLastUpdateTime(partial.item2);
      }
      task.partialApplied = true;
    } catch (_) {
      // 中间态合并失败由最终合并兜底，不影响其他模块继续抓取。
      return;
    }
    for (final listener in task.partialUpdateListeners.toList()) {
      _notifyRefreshListener(listener);
    }
  }

  void _publishFetchStatuses(
      _ScholarRefreshTask task, List<ModuleFetchStatus> statuses) {
    if (statuses.isEmpty) return;
    task.statuses = List.unmodifiable(statuses);
    for (final listener in task.statusListeners.toList()) {
      _notifyRefreshListener(() => listener(task.statuses));
    }
  }

  void _notifyRefreshListener(void Function() listener) {
    try {
      listener();
    } catch (_) {
      // 页面订阅者的异常不应中断抓取或其他订阅者的通知。
    }
  }

  // 把一次抓取结果合并进当前对象。partial 为 true 表示异步刷新的中间态：
  // 空数据、有报错或尚未抓完的部分会被 setScholar 的守卫拦下，保留原值；
  // 实践学分成功与否要等全部抓完才能判定，中间态一律保持不变。
  void _applyFetchResult(EverythingTuple value, {bool partial = false}) {
    var tempSemester = value.item3;
    var tempGrades = value.item4.fold(<String, List<Grade>>{}, (p, e) {
      // 体育课
      var matchClass = RegExp(r'(\(.*\)-(.*?))-.*').firstMatch(e.id);
      var key = matchClass?.group(2) ?? e.id.substring(14, 22);
      if (key.startsWith('PPAE') || key.startsWith('401')) {
        key = matchClass?.group(1) ?? e.id.substring(0, 22);
      }
      var courseIdMappingList =
          Get.find<OptionController>(tag: 'optionController')
              .courseIdMappingList;
      var courseIdMappingMap = {
        for (var e in courseIdMappingList) e.id1: e.id2
      };
      if (courseIdMappingMap.containsKey(key)) {
        key = courseIdMappingMap[key]!;
      }
      p.putIfAbsent(key, () => <Grade>[]).add(e);
      return p;
    });
    var tempMajorGpaAndCredit = value.item5;
    var tempSpecialDates = value.item6;
    var tempTodos = value.item7;

    var tempIsPracticeScoresGet = partial ? isPracticeScoresGet : false;
    var tempPt2 = partial ? pt2 : 0.0;
    var tempPt3 = partial ? pt3 : 0.0;
    var tempPt4 = partial ? pt4 : 0.0;
    if (!partial) {
      // 获取实践学分数据（仅本科生）
      if (_spider is UgrsSpider && !isGrs) {
        var ugrsSpider = _spider as UgrsSpider;
        tempIsPracticeScoresGet = ugrsSpider.isPracticeScoresGet;
        if (tempIsPracticeScoresGet) {
          var practiceScores = ugrsSpider.practiceScores;
          if (practiceScores != null) {
            tempPt2 = practiceScores['pt2'] ?? 0.0;
            tempPt3 = practiceScores['pt3'] ?? 0.0;
            tempPt4 = practiceScores['pt4'] ?? 0.0;
          }
        }
      } else {
        tempIsPracticeScoresGet = false;
      }
    }

    setScholar(
        value.item2,
        tempSemester,
        tempGrades,
        tempMajorGpaAndCredit,
        tempSpecialDates,
        tempTodos,
        tempIsPracticeScoresGet,
        tempPt2,
        tempPt3,
        tempPt4);

    _computeGpas();
  }

  // 由 grades 计算保研/出国 GPA、所获学分，以及主修与推免的派生值
  void _computeGpas() {
    // 保研成绩，只取第一次
    var netGrades = grades.values.map((e) => e.first);
    if (netGrades.isNotEmpty) {
      gpa = GpaHelper.calculateGpa(netGrades).item1;
    }
    // 出国成绩，取最高的一次。排序用副本，保留 grades 内的修读先后顺序
    var aboardNetGrades = grades.values.map((e) {
      var sorted = List<Grade>.of(e)
        ..sort((a, b) => a.hundredPoint.compareTo(b.hundredPoint));
      return sorted.last;
    });
    if (aboardNetGrades.isNotEmpty) {
      var result = GpaHelper.calculateGpa(aboardNetGrades);
      aboardGpa = result.item1;
      // 所获学分，不包括挂科的。
      credit = result.item2;
    } else {
      credit = 0.0;
    }
    recalculateDerivedGpa();
  }

  /// 按当前「主修课程来源」与「推免绩点规则」重算派生值。
  /// 设置变化后调用；不落盘，加载时会重新计算
  void recalculateDerivedGpa() {
    var db = _db;
    _useCustomMajor = db?.getUseCustomMajor() ?? false;
    _majorOverrides = _useCustomMajor ? (db?.getMajorOverrides() ?? {}) : {};

    var allGrades = grades.values.expand((e) => e);
    if (_useCustomMajor) {
      var result = GpaHelper.calculateGpa(allGrades.where(isMajor));
      effectiveMajorGpaAndCredit = [result.item1[0], result.item2];
    } else {
      effectiveMajorGpaAndCredit = List<double>.of(majorGpaAndCredit);
    }

    var rule = db?.getRecommendGpaRule() ?? const RecommendGpaRule();
    var courseWeights = db?.getWeightedGpa() ?? const <String, double>{};
    var firstGrades = grades.values.map((e) => e.first);
    var bestGrades = grades.values.map(
        (e) => e.reduce((a, b) => b.hundredPoint >= a.hundredPoint ? b : a));
    recommendGpa = [
      GpaHelper.calculateRecommendGpa(firstGrades, rule,
          isMajor: isMajor, courseWeights: courseWeights),
      GpaHelper.calculateRecommendGpa(bestGrades, rule,
          isMajor: isMajor, courseWeights: courseWeights),
    ];
  }

  void updateLastUpdateTime(List<String?> errorMessage) {
    var errorItems = ["成绩", "课表", "作业"];
    var errorResult = [false, false, false];

    for (int i = 0; i < errorItems.length; i++) {
      for (var e in errorMessage) {
        if (e != null && e.contains(errorItems[i])) {
          errorResult[i] = true;
          break;
        }
      }
    }
    if (!errorResult[0]) {
      lastUpdateTimeGrade = DateTime.now();
    }
    if (!errorResult[1]) {
      lastUpdateTimeCourse = DateTime.now();
    }
    if (!errorResult[2]) {
      lastUpdateTimeHomework = DateTime.now();
    }
  }

  void setScholar(
      List<String?> errorMessage,
      List<Semester> tempSemesters,
      Map<String, List<Grade>> tempGrades,
      List<double> tempMajorGpaAndCredit,
      Map<DateTime, String> tempSpecialDates,
      List<Todo> tempTodos,
      bool tempIsPracticeScoresGet,
      double tempPt2,
      double tempPt3,
      double tempPt4) {
    var errorItems = ["成绩", "主修", "课表", "作业", "实践"];
    var errorResult = [false, false, false, false, false];

    for (int i = 0; i < errorItems.length; i++) {
      for (var e in errorMessage) {
        if (e != null && e.contains(errorItems[i])) {
          errorResult[i] = true;
          break;
        }
      }
    }

    if (tempSpecialDates.isNotEmpty) {
      specialDates = tempSpecialDates;
    }
    if (errorResult[0] == false && tempGrades.isNotEmpty) {
      grades = tempGrades;
    }
    if (errorResult[1] == false && tempMajorGpaAndCredit.isNotEmpty) {
      majorGpaAndCredit = tempMajorGpaAndCredit;
    }
    if (errorResult[2] == false && tempSemesters.isNotEmpty) {
      semesters = tempSemesters;
    }
    if (errorResult[3] == false && tempTodos.isNotEmpty) {
      todos = tempTodos;
    }
    isPracticeScoresGet = tempIsPracticeScoresGet;
    if (errorResult[4] == false && tempIsPracticeScoresGet) {
      pt2 = tempPt2;
      pt3 = tempPt3;
      pt4 = tempPt4;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'semesters': semesters,
      'grades': grades,
      'gpa': gpa,
      'aboardGpa': aboardGpa,
      'credit': credit,
      'majorGpaAndCredit': majorGpaAndCredit,
      'specialDates':
          specialDates.map((k, v) => MapEntry(k.toIso8601String(), v)),
      'lastUpdateTimeGrade': lastUpdateTimeGrade.toIso8601String(),
      'lastUpdateTimeCourse': lastUpdateTimeCourse.toIso8601String(),
      'lastUpdateTimeHomework': lastUpdateTimeHomework.toIso8601String(),
      'todos': todos,
      'pt2': pt2,
      'pt3': pt3,
      'pt4': pt4,
      'isPracticeScoresGet': isPracticeScoresGet,
    };
  }

  Future<void> recalculateGpa() async {
    grades =
        grades.values.expand((e) => e).fold(<String, List<Grade>>{}, (p, e) {
      // 体育课
      var matchClass = RegExp(r'(\(.*\)-(.*?))-.*').firstMatch(e.id);
      var key = matchClass?.group(2) ?? e.id.substring(14, 22);
      if (key.startsWith('PPAE') || key.startsWith('401')) {
        key = matchClass?.group(1) ?? e.id.substring(0, 22);
      }
      var courseIdMappingList =
          Get.find<OptionController>(tag: 'optionController')
              .courseIdMappingList;
      var courseIdMappingMap = {
        for (var e in courseIdMappingList) e.id1: e.id2
      };
      if (courseIdMappingMap.containsKey(key)) {
        key = courseIdMappingMap[key]!;
      }
      p.putIfAbsent(key, () => <Grade>[]).add(e);
      return p;
    });

    _computeGpas();

    await _db?.setScholar(this);
  }

  Scholar.fromJson(Map<String, dynamic> json, {SpiderFactory? spiderFactory})
      : _spiderFactory = spiderFactory ?? _createSpider {
    username = json.containsKey('username')
        ? json['username']
        : null; // <=0.2.6 Compatibility
    password = json.containsKey('password')
        ? json['password']
        : null; // <=0.2.6 Compatibility
    semesters =
        (json['semesters'] as List).map((e) => Semester.fromJson(e)).toList();
    grades = (json['grades'] as Map<String, dynamic>).map((key, value) {
      return MapEntry(
          key, (value as List).map((e) => Grade.fromJson(e)).toList());
    });
    gpa = List<double>.from(json['gpa']);
    aboardGpa = List<double>.from(json['aboardGpa']);
    credit = json['credit'];
    majorGpaAndCredit = List<double>.from(json['majorGpaAndCredit']);
    specialDates = ((json['specialDates'] ?? {}) as Map)
        .map((k, v) => MapEntry(DateTime.parse(k as String), v as String));
    lastUpdateTimeGrade =
        DateTime.parse(json['lastUpdateTimeGrade'] ?? "20010101");
    lastUpdateTimeCourse =
        DateTime.parse(json['lastUpdateTimeCourse'] ?? "20010101");
    lastUpdateTimeHomework =
        DateTime.parse(json['lastUpdateTimeHomework'] ?? "20010101");
    todos = json.containsKey('todos') // back compatibility
        ? (json['todos'] as List).map((e) => Todo.fromJson(e)).toList()
        : [];
    pt2 = json.containsKey('pt2') ? (json['pt2'] as num).toDouble() : 0.0;
    pt3 = json.containsKey('pt3') ? (json['pt3'] as num).toDouble() : 0.0;
    pt4 = json.containsKey('pt4') ? (json['pt4'] as num).toDouble() : 0.0;
    isPracticeScoresGet = json.containsKey('isPracticeScoresGet')
        ? (json['isPracticeScoresGet'] as bool)
        : false;
    isLogan = true;
    if (gpa.length == 3) {
      gpa.insert(2, 0);
    }
    if (aboardGpa.length == 3) {
      aboardGpa.insert(2, 0);
    }
  }
}

class _ScholarRefreshTask {
  _ScholarRefreshTask(this.startedByUser);

  final bool startedByUser;
  final completer = Completer<List<String?>>();
  bool manualRefreshRequested = false;
  bool asyncRefresh = false;
  int round = 0;
  final partialUpdateListeners = <void Function()>{};
  final statusListeners = <void Function(List<ModuleFetchStatus>)>{};
  List<ModuleFetchStatus> statuses = const [];
  EverythingTuple? latestPartial;
  bool partialApplied = false;
}
