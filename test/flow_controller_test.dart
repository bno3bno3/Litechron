import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/page/flow/flow_controller.dart';

class _Database extends Fake implements DatabaseHelper {
  List<Task> savedTasks = [];
  List<Period> savedPeriods = [];

  @override
  Future<void> setTaskList(List<Task> tasks) async {
    savedTasks = tasks.map((task) => task.copyWith()).toList();
  }

  @override
  Future<void> setFlowList(List<Period> periods) async {
    savedPeriods = periods.map((period) => period.copyWith()).toList();
  }

  @override
  Future<void> setTaskListUpdateTime(DateTime time) async {}

  @override
  Future<void> setFlowListUpdateTime(DateTime time) async {}
}

class _Flow extends FlowController {
  _Flow({required super.now});

  int walks = 0;
  int widgetUpdates = 0;

  @override
  void walkFlowList() {
    walks++;
    super.walkFlowList();
  }

  @override
  void refreshWidget() => widgetUpdates++;
}

class _Fixture {
  _Fixture({DateTime? now, List<Task>? tasks, List<Period>? periods}) {
    clock = now ?? DateTime.now().add(const Duration(days: 1));
    final start = clock.subtract(const Duration(seconds: 10));
    taskList = (tasks ??
            [
              Task(
                uid: 'task',
                summary: '测试任务',
                startTime: start,
                endTime: clock.add(const Duration(hours: 1)),
                repeatEndsTime: clock.add(const Duration(days: 1)),
                timeNeeded: const Duration(hours: 1),
                timeSpent: const Duration(seconds: 9),
              ),
            ])
        .obs;
    flowList = (periods ??
            [
              Period(
                uid: 'flow',
                fromUid: 'task',
                type: PeriodType.flow,
                startTime: start,
                endTime: clock.add(const Duration(minutes: 5)),
                lastUpdateTime: clock.subtract(const Duration(seconds: 1)),
              ),
            ])
        .obs;
    Get.put<DatabaseHelper>(db, tag: 'db');
    Get.put<Rx<Scholar>>(Scholar().obs, tag: 'scholar');
    Get.put<RxList<Task>>(taskList, tag: 'taskList');
    Get.put<RxList<Period>>(flowList, tag: 'flowList');
    Get.put<Rx<DateTime>>(DateTime(2000).obs, tag: 'taskListLastUpdate');
    Get.put<Rx<DateTime>>(DateTime(2000).obs, tag: 'flowListLastUpdate');
    flow = _Flow(now: () => clock);
    Get.put<FlowController>(flow);
  }

  final db = _Database();
  late DateTime clock;
  late final RxList<Task> taskList;
  late final RxList<Period> flowList;
  late final _Flow flow;

  Future<void> advance(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  testWidgets('每秒累计进度并通知界面，不重复完整遍历或推送小组件', (tester) async {
    final fixture = _Fixture();
    var taskChanges = 0;
    var flowChanges = 0;
    final tasks = fixture.taskList.listen((_) => taskChanges++);
    final periods = fixture.flowList.listen((_) => flowChanges++);
    final widgetUpdates = fixture.flow.widgetUpdates;

    await fixture.advance(tester, 4);

    expect(fixture.taskList.single.timeSpent, const Duration(seconds: 14));
    expect(fixture.flow.timeNow.value, fixture.clock);
    expect(fixture.flow.walks, 1);
    expect(fixture.flow.widgetUpdates, widgetUpdates);
    expect(taskChanges, 4);
    expect(flowChanges, 4);
    await tasks.cancel();
    await periods.cancel();
    await Get.delete<FlowController>(force: true);
  });

  testWidgets('外部任务修改仍触发遍历并同步描述，之后恢复按边界调度', (tester) async {
    final fixture = _Fixture();
    fixture.taskList.single.summary = '修改后的任务';
    fixture.taskList.refresh();
    await fixture.advance(tester, 1);
    expect(fixture.flow.walks, 2);
    expect(fixture.flowList.single.summary, '修改后的任务');

    await fixture.advance(tester, 4);
    expect(fixture.flow.walks, 2);

    fixture.flow.scholar.refresh();
    await fixture.advance(tester, 1);
    expect(fixture.flow.walks, 3);
    await Get.delete<FlowController>(force: true);
  });

  testWidgets('跨过结束边界仍清理规划并累计到结束时刻', (tester) async {
    final fixture = _Fixture();
    fixture.flowList.single.endTime =
        fixture.clock.add(const Duration(seconds: 2));
    fixture.flow.walkFlowList();
    await fixture.advance(tester, 4);

    expect(fixture.flowList, isEmpty);
    expect(fixture.taskList.single.timeSpent, const Duration(seconds: 12));
    final walks = fixture.flow.walks;
    await fixture.advance(tester, 3);
    expect(fixture.flow.walks, walks);
    await Get.delete<FlowController>(force: true);
  });

  testWidgets('保留一分钟兜底遍历', (tester) async {
    final fixture = _Fixture();
    await fixture.advance(tester, 59);
    expect(fixture.flow.walks, 1);
    await fixture.advance(tester, 1);
    expect(fixture.flow.walks, 2);
    await Get.delete<FlowController>(force: true);
  });

  testWidgets('进度和时间戳成对保存，恢复后只补计一次关闭期间的时长', (tester) async {
    final fixture = _Fixture();
    await fixture.advance(tester, 15);
    final savedTasks = fixture.db.savedTasks;
    final savedPeriods = fixture.db.savedPeriods;
    final savedAt = savedPeriods.single.lastUpdateTime!;
    expect(savedTasks.single.timeSpent, const Duration(seconds: 25));
    expect(savedAt, fixture.clock);
    await Get.delete<FlowController>(force: true);
    Get.reset();

    final restored = _Fixture(
      now: savedAt.add(const Duration(seconds: 40)),
      tasks: savedTasks,
      periods: savedPeriods,
    );
    expect(restored.taskList.single.timeSpent, const Duration(seconds: 65));
    await restored.advance(tester, 1);
    expect(restored.taskList.single.timeSpent, const Duration(seconds: 66));
    await Get.delete<FlowController>(force: true);
  });

  testWidgets('销毁后停止定时器和学业、任务订阅', (tester) async {
    final fixture = _Fixture();
    await Get.delete<FlowController>(force: true);
    final widgetUpdates = fixture.flow.widgetUpdates;
    final progress = fixture.taskList.single.timeSpent;
    fixture.taskList.refresh();
    fixture.flow.scholar.refresh();
    await fixture.advance(tester, 2);
    expect(fixture.flow.widgetUpdates, widgetUpdates);
    expect(fixture.taskList.single.timeSpent, progress);
  });
}
