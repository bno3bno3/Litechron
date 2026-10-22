import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:litechron/http/spider.dart';
import 'package:litechron/model/todo.dart';
import 'package:litechron/model/semester.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/option.dart';
import 'package:litechron/utils/refresh_time.dart';
import 'todo/todo_filter.dart';

typedef _TodoBuckets = ({
  List<Todo> pending,
  List<Todo> oneDay,
  List<Todo> oneWeek,
  DateTime? nextChange,
});

class ScholarController extends GetxController with WidgetsBindingObserver {
  ScholarController({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _todoNow = _now().obs;
  }

  final DateTime Function() _now;
  late final Rx<DateTime> _todoNow;
  final _scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _option = Get.find<Option>(tag: 'option');

  final Rx<Duration> _durationToLastUpdateGrade = const Duration().obs;
  final Rx<Duration> _durationToLastUpdateCourse = const Duration().obs;
  final Rx<Duration> _durationToLastUpdateHomework = const Duration().obs;

  // 直接初始化为 0，避免 late final 的初始化时机问题
  final RxInt semesterIndex = 0.obs;

  Timer? _timer;
  Worker? _scholarWorker;
  bool _clockStarted = false;
  bool _paused = false;
  Scholar? _todosOwner;
  List<Todo>? _todosSource;
  List<Todo>? _sortedTodos;
  _TodoBuckets? _buckets;
  Semester? _bucketSemester;
  DateTime? _bucketNow;

  // —— 刷新状态文案 ——
  // 刷新超过约 5 秒（第 _statusFirstShowTick 个周期）才开始展示，
  // 之后每个周期轮换一条；文案基于 Scholar.refresh 上报的真实模块进度
  static const int _statusFirstShowTick = 2;
  static const Duration _statusInterval = Duration(milliseconds: 2500);

  // 各抓取模块（本科生与研究生两套标签）的进行中 / 成功 / 失败文案
  static const Map<String, String> _progressCopy = {
    '校历': '正在同步校历...',
    '课表': '正在获取课表...',
    '考试': '正在解析考试安排...',
    '成绩': '正在等待成绩数据...',
    '主修': '正在核对主修成绩...',
    '作业': '正在同步作业列表...',
    '实践': '正在统计实践学分...',
    '配置': '正在同步校历...',
    '本科生课考试': '正在解析本科生考试...',
    '本科生课成绩': '正在等待本科生成绩...',
    '研究生课考试': '正在解析研究生考试...',
    '研究生课成绩': '正在等待研究生成绩...',
  };
  static const Map<String, String> _successCopy = {
    '校历': '校历已更新',
    '课表': '成功获取课表',
    '考试': '成功获取考试安排',
    '成绩': '成功获取考试成绩',
    '主修': '主修成绩已更新',
    '作业': '成功获取作业列表',
    '实践': '实践学分已更新',
    '配置': '校历已更新',
    '本科生课考试': '成功获取本科生考试',
    '本科生课成绩': '成功获取本科生成绩',
    '研究生课考试': '成功获取研究生考试',
    '研究生课成绩': '成功获取研究生成绩',
  };
  static const Map<String, String> _failureCopy = {
    '校历': '校历获取失败',
    '课表': '课表获取失败',
    '考试': '考试安排获取失败',
    '成绩': '成绩获取失败',
    '主修': '主修成绩获取失败',
    '作业': '作业获取失败',
    '实践': '实践学分获取失败',
    '配置': '校历配置获取失败',
    '本科生课考试': '本科生考试获取失败',
    '本科生课成绩': '本科生成绩获取失败',
    '研究生课考试': '研究生考试获取失败',
    '研究生课成绩': '研究生成绩获取失败',
  };
  // 暂无模块进度时的兜底轮播
  static const List<String> _genericCarousel = [
    '正在同步教务数据...',
    '正在等待服务器响应...',
    '仍在努力获取中...',
  ];

  /// 当前展示的刷新状态文案，null 表示不展示
  final Rxn<String> refreshStatusMessage = Rxn<String>();

  Timer? _statusTimer;
  int _statusTick = 0;
  int _activeFetchCount = 0;
  List<ModuleFetchStatus> _statuses = const [];
  final Map<String, FetchModuleState> _seenStates = {};
  final List<String> _announcements = [];
  int _rotation = 0;

  Scholar get scholar => _scholar.value;

  List<Semester> get semesters => _scholar.value.semesters;

  // Getter 保持纯净，不包含任何副作用（不修改状态）
  Semester get selectedSemester {
    final index = semesterIndex.value;

    // 如果学期列表为空，返回当前学期
    if (semesters.isEmpty) {
      return _scholar.value.thisSemester;
    }

    // 如果索引无效，返回当前学期
    if (index < 0 || index >= semesters.length) {
      return _scholar.value.thisSemester;
    }

    // 索引有效，返回对应的学期
    return semesters[index];
  }

  Duration get durationToLastUpdateGrade => _durationToLastUpdateGrade.value;
  Duration get durationToLastUpdateCourse => _durationToLastUpdateCourse.value;
  Duration get durationToLastUpdateHomework =>
      _durationToLastUpdateHomework.value;

  List<double> get gpa {
    var first = _option.gpaStrategy.value == GpaStrategy.first;
    var base = first ? _scholar.value.gpa : _scholar.value.aboardGpa;
    // 展示推免绩点：只替换五分制，其余分制保持原始值
    if (!_option.showRecommendGpa.value) return base;
    var result = List<double>.of(base);
    result[0] = _scholar.value.recommendGpa[first ? 0 : 1];
    return result;
  }

  /// 首页统计和明细页共用同一时刻，避免截止边界处的数字与列表不一致。
  DateTime get todoNow => _todoNow.value;

  List<Todo> get todos {
    final owner = _scholar.value;
    final source = owner.todos;
    if (_sortedTodos != null &&
        identical(owner, _todosOwner) &&
        identical(source, _todosSource)) {
      return _sortedTodos!;
    }
    final indexed = source.indexed.toList();
    indexed.sort((a, b) {
      final aEnd = a.$2.endTime;
      final bEnd = b.$2.endTime;
      if (aEnd == null && bEnd != null) return 1;
      if (aEnd != null && bEnd == null) return -1;
      final order = aEnd == null ? 0 : aEnd.compareTo(bEnd!);
      // List.sort 本身不稳定，用原始下标保留相同时间（含无日期）的顺序。
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
    _todosOwner = owner;
    _todosSource = source;
    _sortedTodos = List<Todo>.unmodifiable(indexed.map((entry) => entry.$2));
    _buckets = null;
    return _sortedTodos!;
  }

  Semester? get _currentSemester =>
      scholar.semesters.isEmpty ? null : scholar.thisSemester;

  _TodoBuckets get _todoBuckets {
    final sorted = todos;
    final now = todoNow;
    final semester = _currentSemester;
    if (_buckets != null &&
        identical(semester, _bucketSemester) &&
        now == _bucketNow) {
      return _buckets!;
    }
    final courseNames =
        semester?.courses.values.map((course) => course.name).toSet() ?? {};
    final pending = <Todo>[];
    final oneDay = <Todo>[];
    final oneWeek = <Todo>[];
    final dayEnd = now.add(const Duration(days: 1));
    final weekEnd = now.add(const Duration(days: 7));
    DateTime? next;
    void consider(DateTime boundary) {
      if (boundary.isAfter(now) && (next == null || boundary.isBefore(next!))) {
        next = boundary;
      }
    }

    for (final todo in sorted) {
      final deadline = todo.endTime;
      if (deadline != null) {
        // 总计页也需要在截止后更新“已截止”标记，保留截止此刻的包含关系。
        consider(deadline.add(const Duration(microseconds: 1)));
      }
      if (!courseNames.contains(todo.course) ||
          (deadline != null && deadline.isBefore(now))) {
        continue;
      }
      pending.add(todo);
      if (deadline == null) continue;
      if (!deadline.isAfter(dayEnd)) oneDay.add(todo);
      if (!deadline.isAfter(weekEnd)) oneWeek.add(todo);
      consider(deadline.subtract(const Duration(days: 1)));
      consider(deadline.subtract(const Duration(days: 7)));
    }
    _bucketSemester = semester;
    _bucketNow = now;
    return _buckets = (
      pending: List<Todo>.unmodifiable(pending),
      oneDay: List<Todo>.unmodifiable(oneDay),
      oneWeek: List<Todo>.unmodifiable(oneWeek),
      nextChange: next,
    );
  }

  List<Todo> get currentSemesterPendingTodos => _todoBuckets.pending;

  List<Todo> todosFor(TodoFilter filter) => switch (filter) {
        TodoFilter.all => todos,
        TodoFilter.oneDay => _todoBuckets.oneDay,
        TodoFilter.oneWeek => _todoBuckets.oneWeek,
      };

  List<Todo> get todosInOneDay => todosFor(TodoFilter.oneDay);

  List<Todo> get todosInOneWeek => todosFor(TodoFilter.oneWeek);

  void _updateDurations({bool forceTodos = false}) {
    final now = _now();
    final nextTodoChange = _buckets?.nextChange;
    if (forceTodos ||
        _buckets == null ||
        now.isBefore(todoNow) ||
        !identical(_bucketSemester, _currentSemester) ||
        (nextTodoChange != null && !now.isBefore(nextTodoChange))) {
      _buckets = null;
      _todoNow.value = now;
    }
    _durationToLastUpdateGrade.value = Duration(
        minutes: now.difference(scholar.lastUpdateTimeGrade).inMinutes);
    _durationToLastUpdateCourse.value = Duration(
        minutes: now.difference(scholar.lastUpdateTimeCourse).inMinutes);
    _durationToLastUpdateHomework.value = Duration(
        minutes: now.difference(scholar.lastUpdateTimeHomework).inMinutes);

    _timer?.cancel();
    if (!_clockStarted || _paused || isClosed) return;
    final boundaries = [
      nextMinuteChange(scholar.lastUpdateTimeGrade, now),
      nextMinuteChange(scholar.lastUpdateTimeCourse, now),
      nextMinuteChange(scholar.lastUpdateTimeHomework, now),
      if (_todoBuckets.nextChange case final boundary?) boundary,
    ];
    final next = boundaries.reduce((a, b) => a.isBefore(b) ? a : b);
    _timer = Timer(next.difference(now), _updateDurations);
  }

  Future<List<String?>> fetchData() async {
    // 并发调用共享最终结果，最后一个调用结束时才收起状态文案。
    _activeFetchCount++;
    if (_activeFetchCount == 1) _startStatusFeed();
    try {
      // 异步刷新开启时，每合并一部分数据就刷新界面和“更新于”时长
      return await _scholar.value
          .refresh(
              userInitiated: true,
              onPartialUpdate: () {
                _scholar.refresh();
                _updateDurations();
              },
              onFetchStatus: _onFetchStatus)
          .then((value) {
        _scholar.refresh();
        _updateDurations();
        return value;
      });
    } finally {
      _activeFetchCount--;
      if (_activeFetchCount == 0) _stopStatusFeed();
    }
  }

  void _startStatusFeed() {
    _statusTick = 0;
    _rotation = 0;
    _statuses = const [];
    _seenStates.clear();
    _announcements.clear();
    refreshStatusMessage.value = null;
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(_statusInterval, (_) => _onStatusTick());
  }

  void _stopStatusFeed() {
    _statusTimer?.cancel();
    _statusTimer = null;
    // 置空即收起；展示组件自行缓存末条文案以配合收起动画
    refreshStatusMessage.value = null;
  }

  void _onFetchStatus(List<ModuleFetchStatus> statuses) {
    if (_statusTimer == null) return; // 刷新已结束的迟到回调，忽略
    if (statuses.isNotEmpty &&
        statuses.every((s) => s.state == FetchModuleState.pending) &&
        _statuses.any((s) => s.state != FetchModuleState.pending)) {
      // 补刷开始：清掉上一轮尚未播报的成功/失败文案，保留加载计时。
      _seenStates.clear();
      _announcements.clear();
      _rotation = 0;
      if (_statusTick >= _statusFirstShowTick) {
        final label = statuses.first.label;
        refreshStatusMessage.value = _progressCopy[label] ?? '正在获取$label...';
      }
    }
    _statuses = statuses;
    // 文案展示开始前就完成的模块不追溯播报
    var announce = _statusTick >= _statusFirstShowTick;
    for (var s in statuses) {
      var prev = _seenStates[s.label];
      if (announce &&
          prev == FetchModuleState.pending &&
          s.state != FetchModuleState.pending) {
        _announcements.add(s.state == FetchModuleState.success
            ? _successCopy[s.label] ?? '成功获取${s.label}'
            : _failureCopy[s.label] ?? '${s.label}获取失败');
      }
      _seenStates[s.label] = s.state;
    }
  }

  void _onStatusTick() {
    _statusTick++;
    if (_statusTick < _statusFirstShowTick) return;
    if (_announcements.isNotEmpty) {
      refreshStatusMessage.value = _announcements.removeAt(0);
      return;
    }
    var pending = _statuses
        .where((s) => s.state == FetchModuleState.pending)
        .toList(growable: false);
    if (pending.isNotEmpty) {
      var label = pending[_rotation++ % pending.length].label;
      refreshStatusMessage.value = _progressCopy[label] ?? '正在获取$label...';
    } else if (_statuses.isNotEmpty) {
      refreshStatusMessage.value = '正在完成刷新...';
    } else {
      refreshStatusMessage.value =
          _genericCarousel[_rotation++ % _genericCarousel.length];
    }
  }

  /// 按当前学期重置学期下标；进页初始化与账号切换后都走这里
  void resetSemesterIndex() {
    final thisSemesterIndex =
        semesters.indexWhere((e) => e.name == _scholar.value.thisSemester.name);
    semesterIndex.value = thisSemesterIndex >= 0 ? thisSemesterIndex : 0;
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _scholarWorker = ever(_scholar, (_) {
      _sortedTodos = null;
      _buckets = null;
      _updateDurations(forceTodos: true);
    });
  }

  @override
  void onReady() {
    super.onReady();
    resetSemesterIndex();
    _clockStarted = true;
    _updateDurations(forceTodos: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      _updateDurations(forceTodos: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _paused = true;
      _timer?.cancel();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockStarted = false;
    _paused = true;
    _timer?.cancel();
    _scholarWorker?.dispose();
    _statusTimer?.cancel();
    super.onClose();
  }
}
