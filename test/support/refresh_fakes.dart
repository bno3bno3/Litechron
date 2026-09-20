import 'dart:async';

import 'package:litechron/database/database_helper.dart';
import 'package:litechron/http/spider.dart';
import 'package:litechron/model/grade.dart';
import 'package:litechron/model/option.dart';
import 'package:litechron/model/recommend_gpa_rule.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/semester.dart';
import 'package:litechron/model/todo.dart';
import 'package:litechron/page/option/option_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const fetchLabels = ['校历', '课表', '考试', '成绩', '主修', '作业', '实践'];
const academicErrors = <String?>[
  null,
  '课表查询出错：需要验证码',
  null,
  '成绩查询出错：请求超时',
  null,
  null,
  null,
];
final oldUpdateTime = DateTime.utc(2025, 1, 1);

EverythingTuple fetchResult({
  List<String?>? errors,
  List<String?> loginErrors = const [null],
  List<Semester> semesters = const [],
  List<Grade> grades = const [],
  List<Todo> todos = const [],
}) =>
    EverythingTuple(
        loginErrors,
        errors ?? List.filled(fetchLabels.length, null),
        semesters,
        grades,
        [],
        {},
        todos);

Grade sampleGrade({bool updated = false}) => Grade({
      'xkkh': '(2025-2026-1)-TEST0001-0000000-1',
      'kcmc': '测试课程',
      'xf': '2.0',
      'cj': updated ? '90' : '80',
      'jd': updated ? '4.5' : '3.5',
    });

Todo sampleTodo(String id) => Todo.fromJson({
      'id': id,
      'title': '测试作业',
      'course_name': '测试课程',
      'end_time': null,
    });

Option refreshOptions() => Option(
      workTime: const Duration(minutes: 45).obs,
      restTime: const Duration(minutes: 15).obs,
      allowTime: <DateTime, DateTime>{}.obs,
      gpaStrategy: GpaStrategy.first.obs,
      pushOnGradeChange: false.obs,
      pushOnDdlReminder: false.obs,
      brightnessMode: BrightnessMode.system.obs,
      courseIdMappingList: <CourseIdMap>[].obs,
      hideHomeGpa: false.obs,
      asyncRefresh: false.obs,
      showRecommendGpa: false.obs,
    );

// 只提供成绩合并用到的设置，不初始化账号、通知或系统日历。
class RefreshOptionController extends GetxController
    implements OptionController {
  @override
  final courseIdMappingList = <CourseIdMap>[].obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RefreshDatabase extends Fake implements DatabaseHelper {
  bool asyncRefresh = false;
  final savedGradeTimes = <DateTime>[];
  final savedCourseTimes = <DateTime>[];
  final savedHomeworkTimes = <DateTime>[];
  Future<void> Function()? onSave;

  @override
  bool getAsyncRefresh() => asyncRefresh;

  // 派生值重算会读取主修来源与推免规则，测试里一律用默认值
  @override
  bool getUseCustomMajor() => false;

  @override
  Map<String, bool> getMajorOverrides() => {};

  @override
  RecommendGpaRule getRecommendGpaRule() => const RecommendGpaRule();

  @override
  Map<String, double> getWeightedGpa() => {};

  @override
  Future<void> setScholar(Scholar scholar) async {
    savedGradeTimes.add(scholar.lastUpdateTimeGrade);
    savedCourseTimes.add(scholar.lastUpdateTimeCourse);
    savedHomeworkTimes.add(scholar.lastUpdateTimeHomework);
    await onSave?.call();
  }
}

class ControlledFetch {
  ControlledFetch(this.onProgress);

  final void Function(EverythingTuple)? onProgress;
  final result = Completer<EverythingTuple>();

  void emit(EverythingTuple partial) => onProgress?.call(partial);
}

class ControlledSpider implements Spider {
  final interactionRequests = <bool>[];
  final fetches = <ControlledFetch>[];
  final _waitingFetches = <int, Completer<ControlledFetch>>{};
  Completer<List<String?>>? loginGate;
  int loginCalls = 0;
  bool _loggedIn = false;

  @override
  List<String> get fetchLabels => const [
        '校历',
        '课表',
        '考试',
        '成绩',
        '主修',
        '作业',
        '实践',
      ];

  @override
  set db(DatabaseHelper? db) {}

  @override
  Future<List<String?>> login() async {
    loginCalls++;
    final gate = loginGate;
    loginGate = null;
    final errors = gate == null ? <String?>[null] : await gate.future;
    _loggedIn = errors.every((e) => e == null);
    return errors;
  }

  @override
  void logout() => _loggedIn = false;

  Future<ControlledFetch> fetchAt(int index) {
    if (index < fetches.length) return Future.value(fetches[index]);
    return _waitingFetches
        .putIfAbsent(index, () => Completer<ControlledFetch>())
        .future;
  }

  @override
  Future<EverythingTuple> getEverything({
    bool allowUserInteraction = false,
    void Function(EverythingTuple partial)? onProgress,
  }) async {
    interactionRequests.add(allowUserInteraction);
    // 与真实 Spider 相同：首次抓取负责初始化会话。
    if (!_loggedIn) {
      final loginErrors = await login();
      if (loginErrors.any((e) => e != null)) {
        return fetchResult(
            loginErrors: loginErrors,
            errors: [for (final label in fetchLabels) '$label查询出错：未登录']);
      }
    }
    final fetch = ControlledFetch(onProgress);
    final index = fetches.length;
    fetches.add(fetch);
    _waitingFetches.remove(index)?.complete(fetch);
    return fetch.result.future;
  }
}

class RefreshFixture {
  final spider = ControlledSpider();
  final db = RefreshDatabase();
  late final Scholar scholar;
  int factoryCalls = 0;

  RefreshFixture() {
    // 走缓存恢复构造器：已有登录状态，但 Spider 和网络会话尚未初始化。
    scholar = Scholar.fromJson(Scholar().toJson(), spiderFactory: (_, __) {
      factoryCalls++;
      return spider;
    })
      ..username = '3200000000'
      ..password = 'test-only'
      ..db = db
      ..lastUpdateTimeGrade = oldUpdateTime
      ..lastUpdateTimeCourse = oldUpdateTime
      ..lastUpdateTimeHomework = oldUpdateTime
      ..grades = {
        'TEST0001': [sampleGrade()]
      }
      ..semesters = [Semester('2024-2025秋冬')]
      ..todos = [sampleTodo('cached')];
  }
}
