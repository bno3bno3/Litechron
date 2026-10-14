import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/model/course.dart';
import 'package:litechron/model/option.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/todo.dart';
import 'package:litechron/page/option/option_controller.dart';
import 'package:litechron/page/scholar/scholar_controller.dart';

import 'refresh_fakes.dart';

Todo todoSample(String name, DateTime? deadline, {String course = '测试课程'}) =>
    Todo.fromJson({
      'id': name,
      'title': name,
      'course_name': course,
      'end_time': deadline?.toIso8601String(),
    });

class TodoFixture extends RefreshFixture {
  DateTime now = DateTime.utc(2026, 10, 14, 4);
  late final ScholarController controller;

  TodoFixture() {
    scholar.semesters.single.courses['TEST0001'] =
        Course.fromUgrsGrade(sampleGrade());
    scholar.todos = [
      todoSample('稍后截止的作业', now.add(const Duration(hours: 3))),
      todoSample('本周稍后的作业', now.add(const Duration(days: 3))),
      todoSample('无日期的作业', null),
    ];
  }

  void bind({bool registerController = true}) {
    Get.put<Rx<Scholar>>(scholar.obs, tag: 'scholar');
    Get.put<Option>(refreshOptions(), tag: 'option');
    Get.put<OptionController>(_TodoOptionController(), tag: 'optionController');
    controller = ScholarController(now: () => now);
    if (registerController) Get.put(controller);
  }

  void expectNoRequests() {
    expect(factoryCalls, 0);
    expect(spider.loginCalls, 0);
    expect(spider.interactionRequests, isEmpty);
  }
}

class _TodoOptionController extends RefreshOptionController {
  @override
  bool get hideHomeGpa => false;
}
