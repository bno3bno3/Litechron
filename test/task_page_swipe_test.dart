import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/page/flow/flow_controller.dart';
import 'package:litechron/page/task/task_controller.dart';
import 'package:litechron/page/task/task_swipe_card.dart';
import 'package:litechron/page/task/task_view.dart';

class _Database extends Fake implements DatabaseHelper {
  int writes = 0;
  List<Task> savedTasks = [];
  DateTime? savedTime;

  @override
  Future<void> setTaskList(List<Task> tasks) async {
    writes++;
    savedTasks = tasks.map((task) => task.copyWith()).toList();
  }

  @override
  Future<void> setTaskListUpdateTime(DateTime time) async => savedTime = time;
}

// Keep the production task controller and page, replacing only native/widget
// work and the planner with observable boundaries.
class _Flow extends FlowController {
  int replans = 0;
  int clears = 0;

  @override
  // The boundary spy intentionally skips native messaging and periodic work.
  // ignore: must_call_super
  void onInit() {}

  @override
  void removeFlowInFlowList() => clears++;

  @override
  int generateNewFlowList(DateTime startsAt) {
    replans++;
    return 0;
  }
}

Task _task(String uid, {bool expired = false, bool fixed = false}) {
  final now = DateTime.now();
  return Task(
    uid: uid,
    summary: '测试任务$uid',
    description: '',
    location: '',
    type: fixed ? TaskType.fixed : TaskType.deadline,
    startTime: now.add(const Duration(days: 1)),
    endTime: now.add(Duration(days: expired ? -1 : 2)),
    repeatEndsTime: now.add(const Duration(days: 10)),
    timeSpent: const Duration(minutes: 20),
    timeNeeded: const Duration(hours: 1),
  );
}

class _Fixture {
  final db = _Database();
  final active = ValueNotifier(true);
  late final RxList<Task> tasks;
  late final _Flow flow;

  _Fixture(List<Task> source) {
    tasks = source.obs;
    Get.put<DatabaseHelper>(db, tag: 'db');
    Get.put<RxList<Task>>(tasks, tag: 'taskList');
    Get.put<Rx<DateTime>>(DateTime(2000).obs, tag: 'taskListLastUpdate');
    Get.put<RxList<Period>>(<Period>[].obs, tag: 'flowList');
    Get.put<Rx<DateTime>>(DateTime(2000).obs, tag: 'flowListLastUpdate');
    Get.put<Rx<Scholar>>(Scholar().obs, tag: 'scholar');
    flow = _Flow();
    Get.put<FlowController>(flow);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(GetCupertinoApp(home: TaskPage(isActive: active)));
    await tester.pumpAndSettle();
    db.writes = 0;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<TaskController>(force: true);
    await Get.delete<FlowController>(force: true);
    active.dispose();
    await tester.pump();
  }
}

Finder _card(String uid) => find.byWidgetPredicate(
    (widget) => widget is TaskSwipeCard && widget.uid == uid);

Future<void> _swipe(WidgetTester tester, String uid, double delta) async {
  await tester.drag(_card(uid), Offset(delta, 0));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  testWidgets('page swipes never save; delete persists and replans once',
      (tester) async {
    final fixture = _Fixture([_task('one')]);
    await fixture.open(tester);
    await _swipe(tester, 'one', -500);
    expect(fixture.tasks, hasLength(1));
    expect(fixture.db.writes, 0);
    expect(fixture.flow.replans, 0);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(fixture.tasks, isEmpty);
    expect(fixture.db.savedTasks, isEmpty);
    expect(fixture.db.savedTime, isNot(DateTime(2000)));
    expect(fixture.flow.replans, 1);
    expect(fixture.flow.clears, 1);
    expect(find.text('没有任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('completion and restore move groups, save progress and replan',
      (tester) async {
    final task = _task('one');
    final fixture = _Fixture([task]);
    await fixture.open(tester);
    await _swipe(tester, 'one', 160);
    expect(fixture.db.writes, 0);
    expect(task.timeSpent, const Duration(minutes: 20));
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();
    expect(task.status, TaskStatus.completed);
    expect(task.timeSpent, task.timeNeeded);
    expect(Get.find<TaskController>().doneDeadlineList, [task]);
    expect(fixture.flow.replans, 1);
    expect(find.text('删除'), findsNothing);

    await _swipe(tester, 'one', 160);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(task.status, TaskStatus.running);
    expect(task.timeSpent, Duration.zero);
    expect(Get.find<TaskController>().todoDeadlineList, [task]);
    expect(fixture.db.savedTasks.single.timeSpent, Duration.zero);
    expect(fixture.db.savedTasks.single.status, TaskStatus.running);
    expect(fixture.flow.replans, 2);
    await fixture.close(tester);
  });

  testWidgets(
      'tab changes, progress refresh and external removal preserve identity',
      (tester) async {
    final fixture = _Fixture([_task('one'), _task('two')]);
    await fixture.open(tester);
    await _swipe(tester, 'one', -140);
    fixture.flow.timeNow.value = DateTime.now();
    fixture.tasks.refresh();
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    fixture.active.value = false;
    await tester.pumpAndSettle();
    fixture.active.value = true;
    expect(find.text('删除'), findsNothing);
    await _swipe(tester, 'one', -140);
    fixture.tasks.removeAt(0);
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsNothing);
    await tester.tap(_card('two'));
    await tester.pumpAndSettle();
    // A stale revealed UID must not consume this tap or delete the next row.
    expect(find.text('附加信息'), findsOneWidget);
    expect(fixture.tasks.single.uid, 'two');
    expect(fixture.flow.replans, 0);
    await fixture.close(tester);
  });

  testWidgets('more menu closes actions and account replacement clears reveal',
      (tester) async {
    final fixture = _Fixture([_task('one')]);
    await fixture.open(tester);
    await _swipe(tester, 'one', -140);
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_circle));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsNothing);
    expect(find.text('删除已完成任务'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await _swipe(tester, 'one', -140);
    fixture.tasks.assignAll([_task('one')]);
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsNothing);
    expect(fixture.db.writes, 0);
    await fixture.close(tester);
  });

  testWidgets('sorting an open row keeps the delete button bound to its UID',
      (tester) async {
    final fixture = _Fixture([_task('one'), _task('two')]);
    await fixture.open(tester);
    await _swipe(tester, 'one', -140);
    fixture.tasks.sort((a, b) => b.endTime.compareTo(a.endTime));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(fixture.tasks.map((task) => task.uid), ['two']);
    expect(fixture.db.savedTasks.single.uid, 'two');
    expect(fixture.flow.replans, 1);
    await fixture.close(tester);
  });

  testWidgets(
      'repeating schedule deletes its template and archived occurrences',
      (tester) async {
    final schedule = _task('schedule', fixed: true)
      ..repeatType = TaskRepeatType.days;
    final archived = schedule.copyWith(
        uid: 'archived', fromUid: schedule.uid, type: TaskType.fixedlegacy);
    final fixture = _Fixture([schedule, archived]);
    await fixture.open(tester);
    await _swipe(tester, 'schedule', 160);
    expect(find.text('完成'), findsNothing);
    expect(fixture.tasks, hasLength(2));
    await _swipe(tester, 'schedule', -160);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(fixture.tasks, isEmpty);
    expect(fixture.db.savedTasks, isEmpty);
    expect(fixture.flow.replans, 1);
    await fixture.close(tester);
  });

  testWidgets(
      'restoring expired DDL keeps expiry; stale UIDs cannot mutate tasks',
      (tester) async {
    final task = _task('expired', expired: true);
    final fixture = _Fixture([task]);
    await fixture.open(tester);
    final controller = Get.find<TaskController>();
    expect(task.status, TaskStatus.failed);
    expect(controller.toggleTaskCompletion(task.uid), isTrue);
    expect(task.status, TaskStatus.completed);
    expect(controller.toggleTaskCompletion(task.uid), isTrue);
    expect(task.status, TaskStatus.failed);
    expect(task.timeSpent, Duration.zero);
    await tester.pumpAndSettle();
    final writes = fixture.db.writes;
    expect(controller.deleteTask('missing'), isFalse);
    expect(controller.toggleTaskCompletion('missing'), isFalse);
    expect(fixture.db.writes, writes);
    await fixture.close(tester);
  });
}
