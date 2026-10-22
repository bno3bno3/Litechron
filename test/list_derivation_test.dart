import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/model/exam.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/semester.dart';
import 'package:litechron/model/course.dart';
import 'package:litechron/page/scholar/exam_list/exam_list_controller.dart';
import 'package:litechron/page/search/search_controller.dart';
import 'package:litechron/page/search/search_view.dart';

import 'support/refresh_fakes.dart';

class _Search extends SearchPageController {
  int evaluations = 0;

  @override
  List<Course> get courseResult {
    evaluations++;
    return super.courseResult;
  }
}

Semester _semesterWithCourses(List<String> names) {
  final semester = Semester('2025-2026秋冬');
  for (var i = 0; i < names.length; i++) {
    final grade = sampleGrade()
      ..id = '(2025-2026-1)-TEST${i.toString().padLeft(4, '0')}-0000000-1'
      ..name = names[i];
    semester.addGrade(grade);
  }
  return semester;
}

Exam _exam(String name, DateTime start) => Exam.empty()
  ..id = name
  ..name = name
  ..time = [start, start.add(const Duration(hours: 2))];

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  testWidgets('搜索列表滚动构建更多卡片时，不重新过滤完整课程列表', (tester) async {
    final scholar = (Scholar()
          ..semesters = [
            _semesterWithCourses(
                List.generate(60, (i) => '课程${i.toString().padLeft(2, '0')}')),
          ])
        .obs;
    Get.put<Rx<Scholar>>(scholar, tag: 'scholar');
    final controller = _Search();
    Get.put<SearchPageController>(controller);
    await tester.pumpWidget(CupertinoApp(home: SearchPage()));
    await tester.pumpAndSettle();
    controller.searchWord.value = '课程';
    await tester.pumpAndSettle();
    expect(find.text('课程00'), findsOneWidget);

    final evaluations = controller.evaluations;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(controller.evaluations, evaluations);

    // 数据刷新后，相同搜索词应立即匹配新课程。
    scholar.value = Scholar()
      ..semesters = [
        _semesterWithCourses(['新增课程'])
      ];
    await tester.pumpAndSettle();
    expect(controller.courseResult.map((course) => course.name), ['新增课程']);
    expect(find.text('新增课程'), findsOneWidget);
    controller.searchWord.value = '不存在';
    await tester.pumpAndSettle();
    expect(controller.courseResult, isEmpty);
    expect(find.text('新增课程'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<SearchPageController>(force: true);
  });

  test('考试按日期和时间分组展示，不改动共享列表或使日程缓存失效', () {
    final early = _exam('早场', DateTime(2026, 1, 10, 8));
    final late = _exam('晚场', DateTime(2026, 1, 10, 14));
    final next = _exam('次日', DateTime(2026, 1, 11, 8));
    final semester = Semester('2025-2026秋冬')..exams.addAll([next, late, early]);
    final cachedPeriods = semester.periods;
    final scholar = (Scholar()..semesters = [semester]).obs;
    Get.put<Rx<Scholar>>(scholar, tag: 'scholar');
    final controller = ExamListController(initialName: semester.name);

    final groups = controller.exams;
    expect(groups, [
      [early, late],
      [next],
    ]);
    expect(semester.exams, [next, late, early]);
    expect(semester.periods, same(cachedPeriods));

    scholar.value = Scholar()
      ..semesters = [Semester(semester.name)..exams.add(early)];
    expect(controller.exams, [
      [early],
    ]);
    controller.onClose();
  });
}
