import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/design/animate_button.dart';
import 'package:litechron/design/multiple_columns.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/semester.dart';
import 'package:litechron/page/scholar/scholar_controller.dart';
import 'package:litechron/page/scholar/scholar_view.dart';
import 'package:litechron/page/scholar/todo/todo_filter.dart';
import 'package:litechron/page/scholar/todo/todo_list_page.dart';

import 'support/todo_fakes.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  Future<void> open(WidgetTester tester, TodoFixture fixture,
      {TodoFilter filter = TodoFilter.all,
      Brightness brightness = Brightness.light,
      double scale = 1}) async {
    fixture.bind();
    await tester.pumpWidget(GetCupertinoApp(
      theme: CupertinoThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: TodoListPage(initialFilter: filter),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // 共享控制器由测试创建，必须在 Flutter 检查残留定时器前释放。
    await Get.delete<ScholarController>(force: true);
    Get.reset();
    await tester.pump();
  }

  test('总计按截止时间稳定排序，无日期置底且不修改源列表', () {
    final fixture = TodoFixture()..bind(registerController: false);
    final now = fixture.now;
    final original = [
      todoSample('无日期一', null),
      todoSample('同时间一', now),
      todoSample('已截止', now.subtract(const Duration(days: 2))),
      todoSample('无日期二', null),
      todoSample('同时间二', now),
      todoSample('其他课程', now.add(const Duration(days: 1)), course: '其他课程'),
    ];
    fixture.scholar.todos = original;
    final expectedOriginal = List.of(original);
    for (var i = 0; i < 3; i++) {
      final sorted = fixture.controller.todosFor(TodoFilter.all);
      expect(sorted.map((todo) => todo.name),
          ['已截止', '同时间一', '同时间二', '其他课程', '无日期一', '无日期二']);
      expect(identical(sorted, original), isFalse);
      fixture.controller.todosFor(TodoFilter.oneDay);
      fixture.controller.todosFor(TodoFilter.oneWeek);
      expect(original, orderedEquals(expectedOriginal));
    }
    fixture.expectNoRequests();
  });

  test('限时分类包含边界，只筛选当前学期未截止且有日期的作业', () {
    final fixture = TodoFixture()..bind(registerController: false);
    final now = fixture.now;
    fixture.scholar.semesters.add(Semester('2023-2024秋冬'));
    fixture.controller.semesterIndex.value = 1;
    fixture.scholar.todos = [
      todoSample('刚截止', now.subtract(const Duration(microseconds: 1))),
      todoSample('此刻截止', now),
      todoSample('一天边界', now.add(const Duration(hours: 24))),
      todoSample('一天之外', now.add(const Duration(hours: 24, microseconds: 1))),
      todoSample('一周边界', now.add(const Duration(hours: 168))),
      todoSample('一周之外', now.add(const Duration(hours: 168, microseconds: 1))),
      todoSample('无日期', null),
      todoSample('其他学期', now.add(const Duration(hours: 1)), course: '往期课程'),
    ];
    expect(fixture.controller.todosInOneDay.map((todo) => todo.name),
        ['此刻截止', '一天边界']);
    expect(fixture.controller.todosInOneWeek.map((todo) => todo.name),
        ['此刻截止', '一天边界', '一天之外', '一周边界']);
    expect(fixture.controller.todos, hasLength(8));
    fixture.scholar.semesters.clear();
    expect(fixture.controller.todosInOneWeek, isEmpty);
    expect(fixture.controller.todos, hasLength(8));
  });

  for (final filter in TodoFilter.values) {
    testWidgets('${filter.label}入口默认选中正确分类，列表与统计一致', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousErrorBuilder = ErrorWidget.builder;
      final fixture = TodoFixture()..bind();
      final page = ScholarPage();
      // ScholarPage 构造时会设置全局错误页；测试保留框架的错误报告。
      ErrorWidget.builder = previousErrorBuilder;
      await tester.pumpWidget(GetCupertinoApp(home: page));
      await tester.pumpAndSettle();
      final overview = tester
          .widgetList<MultipleColumns>(find.byType(MultipleColumns))
          .singleWhere((widget) => widget.titles.first == '总计');
      expect(overview.titles, ['总计', '一天内', '一周内']);
      expect(overview.contents.cast<Text>().map((text) => text.data),
          ['3', '1', '2']);
      final count = fixture.controller.todosFor(filter).length;
      await tester.ensureVisible(find.text(filter.label));
      await tester.tap(find.text(filter.label));
      await tester.pumpAndSettle();
      expect(find.byType(TodoListPage), findsOneWidget);
      expect(
          tester.widget<TodoListPage>(find.byType(TodoListPage)).initialFilter,
          filter);
      expect(find.text('共 $count 项'), findsOneWidget);
      final selected = tester.widget<AnimateButton>(find.ancestor(
          of: find.text(filter.label), matching: find.byType(AnimateButton)));
      final semantics = tester.widget<Semantics>(find
          .ancestor(
              of: find.byWidget(selected), matching: find.byType(Semantics))
          .first);
      expect(semantics.properties.selected, isTrue);

      // 明细页打开期间继续使用首页控制器的时钟，返回后统计同步变化。
      fixture.now = fixture.now.add(const Duration(hours: 4));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final updatedCount = fixture.controller.todosFor(filter).length;
      expect(find.text('共 $updatedCount 项'), findsOneWidget);
      expect(ModalRoute.of(tester.element(find.byType(TodoListPage))),
          isA<CupertinoPageRoute<void>>());
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      expect(find.byType(ScholarPage), findsOneWidget);
      final updatedOverview = tester
          .widgetList<MultipleColumns>(find.byType(MultipleColumns))
          .singleWhere((widget) => widget.titles.first == '总计');
      expect(updatedOverview.contents.cast<Text>().map((text) => text.data),
          ['3', '0', '1']);
      fixture.expectNoRequests();
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }

  testWidgets('页内切换、共享数据刷新和账号切换即时更新且不联网', (tester) async {
    final fixture = TodoFixture();
    await open(tester, fixture);
    expect(find.text('稍后截止的作业'), findsOneWidget);
    expect(find.text('本周稍后的作业'), findsOneWidget);
    await tester.tap(find.text('一天内'));
    await tester.pumpAndSettle();
    expect(find.text('稍后截止的作业'), findsOneWidget);
    expect(find.text('本周稍后的作业'), findsNothing);
    await tester.tap(find.text('一周内'));
    await tester.pumpAndSettle();
    expect(find.text('本周稍后的作业'), findsOneWidget);
    expect(find.text('无日期的作业'), findsNothing);

    fixture.scholar.todos = [todoSample('新获取的作业', fixture.now)];
    Get.find<Rx<Scholar>>(tag: 'scholar').refresh();
    await tester.pumpAndSettle();
    expect(find.text('新获取的作业'), findsOneWidget);
    expect(find.text('共 1 项'), findsOneWidget);

    final next = TodoFixture();
    next.scholar.todos = [todoSample('另一个账号的作业', fixture.now)];
    Get.find<Rx<Scholar>>(tag: 'scholar').value = next.scholar;
    await tester.pumpAndSettle();
    expect(find.text('新获取的作业'), findsNothing);
    expect(find.text('另一个账号的作业'), findsOneWidget);
    next.scholar.semesters.clear();
    Get.find<Rx<Scholar>>(tag: 'scholar').refresh();
    await tester.pumpAndSettle();
    expect(find.text('未来一周内暂无作业截止'), findsOneWidget);
    await tester.tap(find.text('总计'));
    await tester.pumpAndSettle();
    expect(find.text('另一个账号的作业'), findsOneWidget);
    fixture.expectNoRequests();
    next.expectNoRequests();
    await close(tester);
  });

  testWidgets('共用时钟推进后作业移出限时列表，总计保留并标注已截止', (tester) async {
    final fixture = TodoFixture();
    fixture.scholar.todos = [
      todoSample('即将截止', fixture.now.add(const Duration(seconds: 1)))
    ];
    await open(tester, fixture, filter: TodoFilter.oneDay);
    expect(find.text('即将截止'), findsOneWidget);
    fixture.now = fixture.now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(fixture.controller.todosInOneDay, isEmpty);
    expect(fixture.controller.todosInOneWeek, isEmpty);
    expect(find.text('未来一天内暂无作业截止'), findsOneWidget);
    await tester.tap(find.text('总计'));
    await tester.pumpAndSettle();
    expect(find.text('即将截止'), findsOneWidget);
    expect(find.textContaining(' · 已截止'), findsOneWidget);
    expect(find.text('共 1 项'), findsOneWidget);
    await close(tester);
  });

  testWidgets('未来作业随时间进入一天内和一周内的窗口', (tester) async {
    final fixture = TodoFixture();
    fixture.scholar.todos = [
      todoSample('一天窗口', fixture.now.add(const Duration(days: 1, seconds: 1))),
      todoSample('一周窗口', fixture.now.add(const Duration(days: 7, seconds: 1))),
    ];
    await open(tester, fixture, filter: TodoFilter.oneDay);
    expect(fixture.controller.todosInOneDay, isEmpty);
    expect(fixture.controller.todosInOneWeek, hasLength(1));
    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('一天窗口'), findsOneWidget);
    expect(fixture.controller.todosInOneDay, hasLength(1));
    expect(fixture.controller.todosInOneWeek, hasLength(2));
    await close(tester);
  });

  testWidgets('三个分类的空状态文案', (tester) async {
    final fixture = TodoFixture();
    fixture.scholar.todos = [];
    await open(tester, fixture);
    for (final filter in TodoFilter.values) {
      await tester.tap(find.text(filter.label));
      await tester.pumpAndSettle();
      expect(find.text(filter.emptyMessage), findsOneWidget);
      expect(find.text('共 0 项'), findsOneWidget);
    }
    fixture.expectNoRequests();
    await close(tester);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('320px 小屏长标题，${brightness.name}，$scale 倍字体无溢出且日期样式统一',
          (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = TodoFixture();
        fixture.scholar.todos = [
          todoSample('需要换行的长作业名称：阅读课程材料并完成本周的课程分析报告', fixture.now),
          todoSample('未来一周的作业', fixture.now.add(const Duration(days: 3))),
          todoSample('无日期的作业', null),
        ];
        await open(tester, fixture, brightness: brightness, scale: scale);
        // 小屏放大文字后，三个分类仍然保持单行、同高。
        expect(
            TodoFilter.values
                .map((filter) => tester.getSize(find.text(filter.label)).height)
                .toSet(),
            hasLength(1));
        final dates = tester.widgetList<Text>(find.textContaining('截止 2026.'));
        expect(dates, hasLength(2));
        expect(dates.map((text) => text.style).toSet(), hasLength(1));
        expect(dates.first.style!.fontWeight, FontWeight.normal);
        expect(find.text('一天内截止'), findsNothing);
        expect(find.text('无截止日期'), findsOneWidget);
        final local = fixture.now.toLocal();
        String pad(int value) => value.toString().padLeft(2, '0');
        expect(
            find.text('截止 ${local.year}.${pad(local.month)}.${pad(local.day)} '
                '${pad(local.hour)}:${pad(local.minute)}'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await close(tester);
      });
    }
  }

  testWidgets('较高中文行高与大字体不会撑出固定标题', (tester) async {
    final fixture = TodoFixture()..bind();
    await tester.pumpWidget(GetCupertinoApp(
      theme: const CupertinoThemeData(
        textTheme: CupertinoTextThemeData(
          navTitleTextStyle: TextStyle(fontSize: 17, height: 1.35),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const TodoListPage(initialFilter: TodoFilter.all),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    fixture.expectNoRequests();
    await close(tester);
  });
}
