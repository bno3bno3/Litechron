import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/model/option.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/page/calendar/calendar_controller.dart';
import 'package:litechron/page/option/option_controller.dart';
import 'package:litechron/page/scholar/grade_detail/grade_detail_controller.dart';
import 'package:litechron/page/scholar/grade_detail/grade_detail_view.dart';
import 'package:litechron/page/scholar/grade_detail/weighted_gpa_controller.dart';
import 'package:litechron/page/search/search_controller.dart';
import 'package:litechron/worker/fuse.dart';

import 'support/refresh_fakes.dart';

class _Database extends RefreshDatabase {
  int mappingWrites = 0;

  @override
  Map<String, bool> getCustomGpa() => {'example': true};

  @override
  Future<List<Map<String, String>>> getAccountList() async => [];

  @override
  Future<void> setCourseIdMappingList(List<CourseIdMap> mappings) async {
    mappingWrites++;
  }
}

void main() {
  late Rx<Scholar> scholar;
  late _Database db;

  setUp(() {
    Get.testMode = true;
    db = _Database();
    scholar = Scholar().obs;
    Get.put<DatabaseHelper>(db, tag: 'db');
    Get.put<Rx<Scholar>>(scholar, tag: 'scholar');
    Get.put<Option>(refreshOptions(), tag: 'option');
  });
  tearDown(() => Get.reset());

  testWidgets('成绩页仅注册一个监听，重复进页只重置选择状态', (tester) async {
    GradeDetailPage();
    final controller = Get.find<GradeDetailController>();
    expect(scholar.subject.length, 1);
    controller.semesterIndex.value = 3;
    controller.customGpaMode.value = true;
    controller.customGpaSelected.clear();

    GradeDetailPage();
    expect(Get.find<GradeDetailController>(), same(controller));
    expect(scholar.subject.length, 1);
    expect(controller.semesterIndex.value, 0);
    expect(controller.customGpaMode.value, isFalse);
    expect(controller.customGpaSelected, {'example': true});

    await Get.delete<GradeDetailController>(force: true);
    expect(scholar.subject.length, 0);
    GradeDetailPage();
    expect(Get.find<GradeDetailController>(), isNot(same(controller)));
    expect(scholar.subject.length, 1);
  });

  testWidgets('日历、搜索、权重控制器关闭后释放学业订阅', (tester) async {
    final tasks = <Task>[].obs;
    Get.put<RxList<Task>>(tasks, tag: 'taskList');
    Get.put<OptionController>(RefreshOptionController(),
        tag: 'optionController');
    Get.put(CalendarController());
    Get.put(SearchPageController());
    Get.put(WeightedGpaController());
    expect(scholar.subject.length, 3);
    expect(tasks.subject.length, 1);

    await Get.delete<CalendarController>(force: true);
    await Get.delete<SearchPageController>(force: true);
    await Get.delete<WeightedGpaController>(force: true);
    expect(scholar.subject.length, 0);
    expect(tasks.subject.length, 0);
    scholar.refresh();
    tasks.refresh();
  });

  testWidgets('设置控制器关闭后不再因旧订阅写入课程映射', (tester) async {
    Get.put<RxList<Task>>(<Task>[].obs, tag: 'taskList');
    Get.put<RxList<Period>>(<Period>[].obs, tag: 'flowList');
    Get.put<Rx<DateTime>>(DateTime(2000).obs, tag: 'taskListLastUpdate');
    Get.put<Rx<DateTime>>(DateTime(2000).obs, tag: 'flowListLastUpdate');
    Get.put<Rx<Fuse>>(Fuse().obs, tag: 'fuse');
    Get.put(OptionController(), tag: 'optionController');
    final mappings = Get.find<Option>(tag: 'option').courseIdMappingList;
    mappings.add(CourseIdMap(id1: 'a', id2: 'b', comment: '示例'));
    expect(db.mappingWrites, 1);

    await Get.delete<OptionController>(tag: 'optionController', force: true);
    mappings.refresh();
    expect(db.mappingWrites, 1);
    await tester.pump();
  });
}
