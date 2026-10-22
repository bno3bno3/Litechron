import 'package:get/get.dart';

import 'package:litechron/model/semester.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/exam.dart';

class ExamListController extends GetxController {
  final _scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  late final RxInt semesterIndex;

  ExamListController({required String initialName}) {
    semesterIndex = semesters.indexWhere((e) => e.name == initialName).obs;
  }

  Semester get semester => _scholar.value.semesters[semesterIndex.value];
  List<Semester> get semesters => _scholar.value.semesters;
  // 当前页面不展示更新时间，按需读取即可，无需维持一个定时器。
  Duration get durationToLastUpdate =>
      DateTime.now().difference(_scholar.value.lastUpdateTimeCourse);

  List<List<Exam>> get exams {
    // 展示排序使用副本，避免改变共享考试顺序并使 Semester.periods 缓存失效。
    final sorted = List<Exam>.of(semester.exams)
      ..sort((a, b) => a.time.first.compareTo(b.time.first));
    return sorted.fold(<List<Exam>>[], (previousValue, element) {
      if (previousValue.isEmpty) {
        previousValue.add([element]);
      } else {
        if (previousValue.last[0].time[0].year == element.time[0].year &&
            previousValue.last[0].time[0].month == element.time[0].month &&
            previousValue.last[0].time[0].day == element.time[0].day) {
          previousValue.last.add(element);
        } else {
          previousValue.add([element]);
        }
      }
      return previousValue;
    });
  }
}
