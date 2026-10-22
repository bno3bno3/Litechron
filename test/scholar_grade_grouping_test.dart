import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/model/grade.dart';
import 'package:litechron/model/option.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/page/option/option_controller.dart';

import 'support/refresh_fakes.dart';

class _Options extends GetxController implements OptionController {
  final mappings = <CourseIdMap>[].obs;
  int mappingReads = 0;

  @override
  RxList<CourseIdMap> get courseIdMappingList {
    mappingReads++;
    return mappings;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Grade _grade(String course,
        {String semester = '2025-2026-1', bool updated = false}) =>
    sampleGrade(updated: updated)..id = '($semester)-$course-0000000-1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Options options;

  setUp(() {
    Get.testMode = true;
    options = _Options();
    Get.put<OptionController>(options, tag: 'optionController');
  });
  tearDown(() => Get.reset());

  Future<Scholar> refreshGrades(List<Grade> grades) async {
    final spider = ControlledSpider();
    final scholar = Scholar(spiderFactory: (_, __) => spider)
      ..db = RefreshDatabase()
      ..isLogan = true
      ..username = 'mock-account'
      ..password = 'mock-password';
    final refresh = scholar.refresh();
    (await spider.fetchAt(0)).result.complete(fetchResult(grades: grades));
    expect(await refresh, everyElement(isNull));
    return scholar;
  }

  test('刷新与手动重算共用映射归组，保留首次、最高成绩和学分口径', () async {
    options.mappings
        .add(CourseIdMap(id1: 'OLD00001', id2: 'NEW00001', comment: '示例课程号变更'));
    final first = _grade('OLD00001');
    final second = _grade('NEW00001', updated: true);
    final other = _grade('OTHER001')..fivePoint = 4.0;
    final scholar = await refreshGrades([first, second, other]);

    expect(options.mappingReads, 1);
    expect(scholar.grades.keys, ['NEW00001', 'OTHER001']);
    expect(scholar.grades['NEW00001'], [first, second]);
    expect(scholar.gpa.first, 3.75);
    expect(scholar.aboardGpa.first, 4.25);
    expect(scholar.credit, 4.0);
    final gpa = List<double>.of(scholar.gpa);
    final best = List<double>.of(scholar.aboardGpa);

    await scholar.recalculateGpa();
    expect(options.mappingReads, 2);
    expect(scholar.grades['NEW00001'], [first, second]);
    expect(scholar.gpa, gpa);
    expect(scholar.aboardGpa, best);

    options.mappings.clear();
    await scholar.recalculateGpa();
    expect(options.mappingReads, 3);
    expect(scholar.grades.keys, ['OLD00001', 'NEW00001', 'OTHER001']);
    expect(scholar.credit, 6.0);
  });

  test('体育课和 401 课程按学期分开，普通课跨学期仍归组为重修', () async {
    final grades = [
      _grade('PPAE0001', semester: '2024-2025-1'),
      _grade('PPAE0001'),
      _grade('40100001', semester: '2024-2025-1'),
      _grade('40100001'),
      _grade('TEST0001', semester: '2024-2025-1'),
      _grade('TEST0001'),
    ];
    final scholar = await refreshGrades(grades);
    expect(options.mappingReads, 1);
    expect(scholar.grades.keys, [
      '(2024-2025-1)-PPAE0001',
      '(2025-2026-1)-PPAE0001',
      '(2024-2025-1)-40100001',
      '(2025-2026-1)-40100001',
      'TEST0001',
    ]);
    expect(scholar.grades['TEST0001'], grades.sublist(4));
    await scholar.recalculateGpa();
    expect(scholar.grades['TEST0001'], grades.sublist(4));
    expect(scholar.grades, hasLength(5));
  });

  test('无正则匹配的旧格式课程号仍使用原有截取规则', () async {
    final normal = _grade('TEST0001')..id = '12345678901234TEST0001-suffix';
    final sports = _grade('PPAE0001')..id = '12345678901234PPAE0001-suffix';
    final scholar = await refreshGrades([normal, sports]);
    expect(scholar.grades.keys, ['TEST0001', '12345678901234PPAE0001']);
  });
}
