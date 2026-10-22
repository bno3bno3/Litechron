import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/practice_details.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/page/flow/flow_controller.dart';
import 'package:litechron/page/scholar/practice_score/practice_score_controller.dart';
import 'package:litechron/page/scholar/scholar_controller.dart';
import 'package:litechron/page/task/task_controller.dart';

import 'support/refresh_fakes.dart';
import 'support/todo_fakes.dart';

class _Database extends RefreshDatabase {
  int taskWrites = 0;

  @override
  Future<void> setTaskList(List<Task> tasks) async => taskWrites++;

  @override
  Future<void> setTaskListUpdateTime(DateTime time) async {}

  @override
  Future<void> setFlowList(List<Period> periods) async {}

  @override
  Future<void> setFlowListUpdateTime(DateTime time) async {}
}

class _Tasks extends TaskController {
  _Tasks({required super.now});
  int checks = 0;

  @override
  bool updateDeadlineList() {
    checks++;
    return super.updateDeadlineList();
  }
}

class _TasksFixture {
  DateTime now = DateTime.now().add(const Duration(days: 1));
  final db = _Database();
  final tasks = <Task>[].obs;
  late _Tasks controller;

  Task task(String uid, Duration until, {TaskType type = TaskType.deadline}) =>
      Task(
        uid: uid,
        summary: '测试任务',
        type: type,
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now.add(until),
        repeatEndsTime: now.add(const Duration(days: 7)),
        repeatType: TaskRepeatType.days,
        timeSpent: Duration.zero,
        timeNeeded: const Duration(hours: 1),
      );

  void bind() {
    Get.put<DatabaseHelper>(db, tag: 'db');
    Get.put<RxList<Task>>(tasks, tag: 'taskList');
    Get.put<Rx<DateTime>>(DateTime(2000).obs, tag: 'taskListLastUpdate');
    controller = _Tasks(now: () => now);
    Get.put<TaskController>(controller);
  }

  Future<void> advance(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }
}

class _PracticeScholar extends Scholar {
  _PracticeScholar(this.cache);
  final PracticeDetails cache;

  @override
  PracticeDetails get cachedPracticeDetails => cache;
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() async {
    await Get.deleteAll(force: true);
    Get.reset();
  });

  testWidgets('历史任务不导致定时扫描，外部任务修改仍会重新安排边界', (tester) async {
    final fixture = _TasksFixture();
    final active = fixture.task('active', const Duration(hours: 1));
    fixture.tasks.add(active);
    for (var i = 0; i < 50; i++) {
      fixture.tasks.add(fixture.task('done$i', const Duration(days: -1))
        ..timeSpent = const Duration(hours: 1)
        ..status = TaskStatus.completed);
    }
    fixture.bind();
    final initialWrites = fixture.db.taskWrites;
    await fixture.advance(tester, const Duration(seconds: 30));
    expect(fixture.controller.checks, 1);
    expect(fixture.db.taskWrites, initialWrites);
    expect(fixture.controller.doneDeadlineList, hasLength(50));

    active.endTime = fixture.now.add(const Duration(seconds: 2));
    fixture.tasks.refresh();
    await tester.pump();
    expect(fixture.controller.checks, 2);
    await fixture.advance(tester, const Duration(seconds: 2));
    expect(active.status, TaskStatus.running);
    await fixture.advance(tester, const Duration(microseconds: 1));
    expect(active.status, TaskStatus.failed);
    expect(fixture.controller.checks, 3);
    expect(fixture.db.taskWrites, initialWrites + 1);
    expect(fixture.tasks, hasLength(51));
    await Get.delete<TaskController>(force: true);
  });

  testWidgets('真实 Flow 每秒累计进度时不会让任务控制器重新扫描全表', (tester) async {
    final fixture = _TasksFixture();
    final task = fixture.task('active', const Duration(hours: 1));
    fixture.tasks.add(task);
    fixture.bind();
    Get.put<Rx<Scholar>>(Scholar().obs, tag: 'scholar');
    Get.put<Rx<DateTime>>(DateTime(2000).obs, tag: 'flowListLastUpdate');
    Get.put<RxList<Period>>(
        [
          Period(
            type: PeriodType.flow,
            fromUid: task.uid,
            startTime: fixture.now,
            endTime: fixture.now.add(const Duration(minutes: 10)),
          ),
        ].obs,
        tag: 'flowList');
    Get.put(FlowController(now: () => fixture.now));
    for (var i = 0; i < 10; i++) {
      await fixture.advance(tester, const Duration(seconds: 1));
    }
    expect(task.timeSpent, const Duration(seconds: 10));
    expect(fixture.controller.checks, 1);
    await Get.delete<FlowController>(force: true);
    await Get.delete<TaskController>(force: true);
  });

  testWidgets('后台暂停检查，恢复前台后补齐失败状态与重复日程历史', (tester) async {
    final fixture = _TasksFixture();
    final deadline = fixture.task('ddl', const Duration(hours: 1));
    final fixed =
        fixture.task('fixed', const Duration(hours: 1), type: TaskType.fixed);
    fixture.tasks.addAll([deadline, fixed]);
    fixture.bind();
    fixture.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await fixture.advance(tester, const Duration(days: 3));
    expect(fixture.controller.checks, 1);
    expect(deadline.status, TaskStatus.running);

    fixture.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(fixture.controller.checks, 2);
    expect(deadline.status, TaskStatus.failed);
    expect(fixed.endTime, fixture.now.add(const Duration(hours: 1)));
    expect(fixture.tasks.where((task) => task.type == TaskType.fixedlegacy),
        hasLength(3));
    await Get.delete<TaskController>(force: true);
  });

  testWidgets('连续多次任务通知合并检查，销毁后不再处理旧事件', (tester) async {
    final fixture = _TasksFixture();
    fixture.tasks.add(fixture.task('ddl', const Duration(hours: 1)));
    fixture.bind();
    fixture.tasks.refresh();
    fixture.tasks.refresh();
    fixture.tasks.refresh();
    await tester.pump();
    expect(fixture.controller.checks, 2);
    await Get.delete<TaskController>(force: true);
    fixture.tasks.refresh();
    await fixture.advance(tester, const Duration(hours: 2));
    expect(fixture.controller.checks, 2);
  });

  testWidgets('作业排序与三组筛选共用缓存，仅在窗口和截止边界更新', (tester) async {
    final fixture = TodoFixture();
    fixture.scholar.todos = [
      todoSample('截止窗口', fixture.now.add(const Duration(seconds: 2))),
      todoSample('一天窗口', fixture.now.add(const Duration(days: 1, seconds: 1))),
      todoSample('一周窗口', fixture.now.add(const Duration(days: 7, seconds: 1))),
      todoSample('无日期', null),
    ];
    fixture.bind();
    await tester.pumpWidget(const SizedBox.shrink());
    final sorted = fixture.controller.todos;
    final day = fixture.controller.todosInOneDay;
    final week = fixture.controller.todosInOneWeek;
    expect(day.map((todo) => todo.name), ['截止窗口']);
    expect(week, hasLength(2));
    expect(fixture.controller.todos, same(sorted));
    expect(fixture.controller.todosInOneDay, same(day));
    expect(fixture.controller.todosInOneWeek, same(week));

    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.controller.todosInOneDay, hasLength(2));
    expect(fixture.controller.todosInOneWeek, hasLength(3));
    expect(fixture.controller.todos, same(sorted));
    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.controller.todosInOneDay, hasLength(2));
    fixture.now = fixture.now.add(const Duration(microseconds: 1));
    await tester.pump(const Duration(microseconds: 1));
    expect(fixture.controller.todosInOneDay.map((todo) => todo.name), ['一天窗口']);
    expect(fixture.controller.todosInOneWeek, hasLength(2));
    expect(fixture.controller.todos, same(sorted));

    sorted[1].endTime = fixture.now.subtract(const Duration(days: 1));
    Get.find<Rx<Scholar>>(tag: 'scholar').refresh();
    expect(fixture.controller.todos, isNot(same(sorted)));
    expect(fixture.controller.todos.first.name, '一天窗口');
    fixture.expectNoRequests();
    await Get.delete<ScholarController>(force: true);
  });

  testWidgets('分钟文案只在对应值改变时重建，时钟变化不重排作业', (tester) async {
    final fixture = TodoFixture();
    fixture.scholar.todos = [];
    fixture.scholar.lastUpdateTimeGrade =
        fixture.now.subtract(const Duration(seconds: 20));
    fixture.scholar.lastUpdateTimeCourse =
        fixture.now.subtract(const Duration(seconds: 35));
    fixture.scholar.lastUpdateTimeHomework =
        fixture.now.subtract(const Duration(seconds: 10));
    fixture.bind();
    var builds = 0;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Obx(() {
        builds++;
        return Text(
            '${fixture.controller.durationToLastUpdateGrade.inMinutes}');
      }),
    ));
    await tester.pump();
    final initialBuilds = builds;
    final sorted = fixture.controller.todos;
    final day = fixture.controller.todosInOneDay;
    fixture.now = fixture.now.add(const Duration(seconds: 39));
    await tester.pump(const Duration(seconds: 39));
    expect(builds, initialBuilds);
    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    expect(builds, initialBuilds + 1);
    expect(fixture.controller.todos, same(sorted));
    expect(fixture.controller.todosInOneDay, same(day));
    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<ScholarController>(force: true);
  });

  testWidgets('实践更新时间按缓存时间的分钟边界更新，恢复前台立即补查', (tester) async {
    var now = DateTime(2026, 10, 23, 12);
    final scholar = _PracticeScholar(
        PracticeDetails(updatedAt: now.subtract(const Duration(seconds: 20))));
    final controller = PracticeScoreController(
        initialCategory: 1, scholar: scholar.obs, now: () => now);
    Get.put(controller);
    var changes = 0;
    final clock = controller.now.listen((_) => changes++);
    expect(controller.updateText, '更新于 0 分钟前');
    now = now.add(const Duration(seconds: 39));
    await tester.pump(const Duration(seconds: 39));
    expect(changes, 0);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.updateText, '更新于 1 分钟前');
    expect(changes, 1);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(changes, 1);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(controller.updateText, '更新于 3 分钟前');
    expect(changes, 2);
    await clock.cancel();
    await Get.delete<PracticeScoreController>(force: true);
  });
}
