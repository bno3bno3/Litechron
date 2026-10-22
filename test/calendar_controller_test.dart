import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/page/calendar/calendar_controller.dart';
import 'package:litechron/utils/task_updates.dart';
import 'package:table_calendar/table_calendar.dart';

class _Scholar extends Scholar {
  final List<Period> entries;
  int queries = 0;

  _Scholar(this.entries);

  @override
  List<Period> get periods {
    queries++;
    return entries;
  }
}

class _Task extends Task {
  int queries = 0;

  _Task(DateTime day, {super.type = TaskType.fixed})
      : super(
          uid: 'test-task',
          summary: '测试日程',
          startTime: day.add(const Duration(hours: 10)),
          endTime: day.add(const Duration(hours: 11)),
          repeatEndsTime: day.add(const Duration(days: 366)),
        );

  @override
  List<Period> getPeriodOfDay(DateTime date) {
    queries++;
    return super.getPeriodOfDay(date);
  }
}

Period _period(String name, DateTime start, {PeriodType? type}) => Period(
      uid: name,
      fromUid: name,
      summary: name,
      type: type ?? PeriodType.classes,
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
    );

List<Object?> _signature(Period event) => [
      event.type,
      event.summary,
      event.startTime,
      event.endTime,
      event.fromUid,
      event.fromFromUid,
    ];

void main() {
  final day = DateTime(2026, 10, 23);
  late _Scholar academic;
  late Rx<Scholar> scholar;
  late RxList<Task> tasks;

  CalendarController bind() => Get.put(CalendarController());

  setUp(() {
    Get.testMode = true;
    academic = _Scholar([]);
    scholar = Rx<Scholar>(academic);
    tasks = <Task>[].obs;
    Get.put<Rx<Scholar>>(scholar, tag: 'scholar');
    Get.put<RxList<Task>>(tasks, tag: 'taskList');
  });
  tearDown(() => Get.reset());

  test('学业索引完成分组排序后只发布一次，并清除旧日期缓存', () {
    academic.entries.add(_period('旧课程', day));
    final controller = bind();
    controller.getEventsForDay(day);
    final late = _period('晚课', day.add(const Duration(hours: 14)));
    final early = _period('早课', day.add(const Duration(hours: 8)));
    final nextDay = _period('次日考试', day.add(const Duration(days: 1)),
        type: PeriodType.test);
    final snapshots = <Map<DateTime, List<String>>>[];
    final worker = ever(controller.events, (index) {
      snapshots.add(index.map((date, events) =>
          MapEntry(date, events.map((event) => event.summary).toList())));
      expect(controller.getEventsForDay(day).map((event) => event.summary),
          ['早课', '晚课']);
    });

    academic.entries
      ..clear()
      ..addAll([late, nextDay, early]);
    scholar.refresh();

    expect(snapshots, [
      {
        day: ['早课', '晚课'],
        day.add(const Duration(days: 1)): ['次日考试'],
      }
    ]);
    expect(academic.entries, [late, nextDay, early]);
    worker.dispose();
  });

  test('同一天的标记与详情共享展开结果，只查询固定日程并保留时间排序', () {
    academic.entries.addAll([
      _period('晚课', day.add(const Duration(hours: 14))),
      _period('早课', day.add(const Duration(hours: 8))),
    ]);
    final fixed = _Task(day);
    final ddl = _Task(day, type: TaskType.deadline);
    tasks.addAll([fixed, ddl]);
    final controller = bind();

    final markers = controller.getMarkersForDay(day);
    expect(markers.map((event) => event.hour), [8, 10, 14]);
    expect(
        controller
            .getEventsForDay(day.add(const Duration(hours: 20)))
            .map((event) => event.summary),
        ['早课', '测试日程', '晚课']);
    expect(
        controller.getMarkersForDay(DateTime.utc(2026, 10, 23)), same(markers));
    expect(fixed.queries, 1);
    expect(ddl.queries, 0);
    expect(academic.queries, 1);
  });

  test('详情可修改副本，标记列表不可修改，均不污染学业和日程缓存', () {
    final course = _period('课程', day.add(const Duration(hours: 8)));
    academic.entries.add(course);
    final fixed = _Task(day);
    final legacy = _Task(day, type: TaskType.fixedlegacy)
      ..uid = 'history'
      ..fromUid = 'original-fixed'
      ..startTime = day.add(const Duration(hours: 12))
      ..endTime = day.add(const Duration(hours: 13));
    tasks.addAll([fixed, legacy]);
    final controller = bind();
    final markers = controller.getMarkersForDay(day);
    expect(markers.map((event) => event.colorUid),
        ['课程', 'test-task', 'original-fixed']);
    expect(() => markers.clear(), throwsUnsupportedError);

    final editable = controller.getEventsForDay(day);
    for (final event in editable) {
      event.summary = '副本改名';
      event.startTime = day;
      event.fromUid = '副本来源';
    }
    editable.clear();

    expect(controller.getEventsForDay(day).map((event) => event.summary),
        ['课程', '测试日程', '测试日程']);
    expect(course.summary, '课程');
    expect(course.startTime.hour, 8);
    expect(fixed.uid, 'test-task');
    expect(legacy.fromUid, 'original-fixed');
    expect(controller.getMarkersForDay(day), same(markers));
    expect(markers.map((event) => event.hour), [8, 10, 12]);
  });

  test('日程新增、编辑、移日、删除和学业账号切换后查询立即更新', () {
    final controller = bind();
    expect(controller.getEventsForDay(day), isEmpty);
    final fixed = _Task(day);
    tasks.add(fixed);
    expect(controller.getEventsForDay(day).single.summary, '测试日程');

    fixed.summary = '修改后的日程';
    tasks.refresh();
    expect(controller.getEventsForDay(day).single.summary, '修改后的日程');

    fixed.startTime = fixed.startTime.add(const Duration(days: 1));
    fixed.endTime = fixed.endTime.add(const Duration(days: 1));
    tasks.refresh();
    expect(controller.getEventsForDay(day), isEmpty);
    expect(
        controller
            .getEventsForDay(day.add(const Duration(days: 1)))
            .single
            .summary,
        '修改后的日程');

    tasks.remove(fixed);
    expect(
        controller.getEventsForDay(day.add(const Duration(days: 1))), isEmpty);
    // 日程变化无需重新读取和建立整学期的学业索引。
    expect(academic.queries, 1);

    scholar.value = _Scholar([_period('另一账号课程', day)]);
    expect(controller.getEventsForDay(day).single.summary, '另一账号课程');
    scholar.value = Scholar();
    expect(controller.getEventsForDay(day), isEmpty);
  });

  test('Flow 纯进度通知保留缓存，正常任务变动仍失效', () {
    final fixed = _Task(day);
    tasks.add(fixed);
    final controller = bind();
    final markers = controller.getMarkersForDay(day);

    TaskUpdates.refreshProgress(tasks);
    expect(controller.getMarkersForDay(day), same(markers));
    expect(fixed.queries, 1);

    tasks.refresh();
    expect(controller.getMarkersForDay(day), isNot(same(markers)));
    expect(fixed.queries, 2);
  });

  test('缓存沿用按天、按月、按年、指定日期、跨午夜和历史日程的展开规则', () {
    final controller = bind();
    for (final repeatType in TaskRepeatType.values) {
      final task = _Task(day)
        ..repeatType = repeatType
        ..repeatPeriod = 2
        ..repeatDates = [day, day.add(const Duration(days: 3))]
        ..startTime = day.add(const Duration(hours: 23))
        ..endTime = day.add(const Duration(days: 1, hours: 1));
      tasks.assignAll([task]);
      for (final offset in [0, 1, 2, 3, 4, 31, 365]) {
        final date = day.add(Duration(days: offset));
        expect(controller.getEventsForDay(date).map(_signature).toList(),
            task.getPeriodOfDay(date).map(_signature).toList(),
            reason: '$repeatType / $date');
      }
    }
    final history = _Task(day, type: TaskType.fixedlegacy)
      ..uid = 'history'
      ..fromUid = 'repeat-original'
      ..startTime = day.add(const Duration(hours: 23))
      ..endTime = day.add(const Duration(days: 1, hours: 1));
    tasks.assignAll([history]);
    final next = controller.getEventsForDay(day.add(const Duration(days: 1)));
    expect(next.single.startTime, day.add(const Duration(days: 1)));
    expect(next.single.endTime, day.add(const Duration(days: 1, hours: 1)));
    expect(next.single.fromFromUid, 'repeat-original');
  });

  test('长期翻月会淘汰旧日期，最近访问的日期继续复用', () {
    final task = _Task(day);
    tasks.add(task);
    final controller = bind();
    final first = controller.getMarkersForDay(day);
    for (var offset = 1; offset < 128; offset++) {
      controller.getMarkersForDay(day.add(Duration(days: offset)));
    }
    expect(task.queries, 128);
    expect(controller.getMarkersForDay(day), same(first));
    controller.getMarkersForDay(day.add(const Duration(days: 128)));
    expect(task.queries, 129);
    expect(controller.getMarkersForDay(day), same(first));
    controller.getMarkersForDay(day.add(const Duration(days: 1)));
    expect(task.queries, 130);
  });

  testWidgets('命中缓存后日程和学业变化仍重绘月历标记及当前日详情', (tester) async {
    final fixed = _Task(day);
    tasks.add(fixed);
    final controller = bind();
    // 先填充缓存，确保 Obx 不依赖首次展开时偶然读取到的任务列表。
    controller.getMarkersForDay(day);
    controller.getEventsForDay(day);
    await tester.pumpWidget(CupertinoApp(
      home: Column(children: [
        Obx(() => TableCalendar<CalendarEventMarker>(
              headerVisible: false,
              firstDay: day.subtract(const Duration(days: 50)),
              lastDay: day.add(const Duration(days: 50)),
              focusedDay: day,
              eventLoader: controller.markerLoader,
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, markers) => isSameDay(date, day)
                    ? Text('markers:${markers.length}')
                    : const SizedBox.shrink(),
              ),
            )),
        Obx(() => Text(controller
            .getEventsForDay(day)
            .map((event) => event.summary)
            .join(','))),
      ]),
    ));
    await tester.pump();
    expect(find.text('markers:1'), findsOneWidget);
    expect(find.text('测试日程'), findsOneWidget);

    fixed.summary = '改名日程';
    tasks.refresh();
    await tester.pump();
    expect(find.text('改名日程'), findsOneWidget);
    expect(find.text('测试日程'), findsNothing);

    academic.entries.add(_period('新增课程', day.add(const Duration(hours: 8))));
    scholar.refresh();
    await tester.pump();
    expect(find.text('markers:2'), findsOneWidget);
    expect(find.text('新增课程,改名日程'), findsOneWidget);

    scholar.value = Scholar();
    await tester.pump();
    expect(find.text('markers:1'), findsOneWidget);
    expect(find.text('改名日程'), findsOneWidget);

    tasks.clear();
    await tester.pump();
    expect(find.text('markers:0'), findsOneWidget);
    expect(find.text('改名日程'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
