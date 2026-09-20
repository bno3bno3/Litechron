import 'package:litechron/database/database_helper.dart';
import 'package:get/get.dart';

import 'package:litechron/model/grade.dart';
import 'package:litechron/model/option.dart';
import 'package:litechron/model/semester.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/utils/tuple.dart';
import 'package:litechron/utils/gpa_helper.dart';

class GradeDetailController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _option = Get.find<Option>(tag: 'option');
  final semesterIndex = 0.obs;
  final customGpaMode = false.obs;
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  final RxMap<String, bool> customGpaSelected = RxMap();
  late RxList<Semester> semestersWithGrades;

  void init() {
    semestersWithGrades = scholar.value.semesters
        .where((element) => element.grades.isNotEmpty)
        .toList()
        .obs;
    ever(scholar, (callback) => refreshSemesters());
    customGpaSelected.value = _db.getCustomGpa();
    semesterIndex.value = 0;
    customGpaMode.value = false;
  }

  @override
  void onInit() {
    init();
    super.onInit();
  }

  void refreshSemesters() {
    semestersWithGrades.value = scholar.value.semesters
        .where((element) => element.grades.isNotEmpty)
        .toList();
    semestersWithGrades.refresh();
  }

  void refreshCustomGpa() {
    _db.setCustomGpa(customGpaSelected);
  }

  Tuple<List<double>, double> getYearMajorGpa(int semesterIndex) {
    // 提取当前学期的学年 ID，例如 "2022-2023"
    final yearId = semestersWithGrades[semesterIndex].name.substring(0, 9);

    // 获取该学年的所有主修课程（按「主修课程来源」口径）
    final majorGrades = scholar.value.grades.values
        .expand((g) => g)
        .where((g) => scholar.value.isMajor(g) && g.semesterId.contains(yearId))
        .toList();

    // 如果该学年没有主修课程，返回 0.0, 0.0, 0.0
    if (majorGrades.isEmpty) {
      return Tuple([0.0, 0.0, 0.0], 0.0);
    }

    return GpaHelper.calculateGpa(majorGrades);
  }

  /// 展示推免绩点开启时，学年均绩按推免规则计算（五分制）
  double getYearRecommendGpa(Iterable<Grade> yearGrades) {
    return GpaHelper.calculateRecommendGpa(
        yearGrades, _db.getRecommendGpaRule(),
        isMajor: scholar.value.isMajor, courseWeights: _db.getWeightedGpa());
  }

  bool get showRecommendGpa => _option.showRecommendGpa.value;

  /// 检查指定学期的所有课程是否已全选
  bool isSemesterAllSelected(int semesterIndex) {
    if (semesterIndex < 0 || semesterIndex >= semestersWithGrades.length) {
      return false;
    }
    final semester = semestersWithGrades[semesterIndex];
    if (semester.grades.isEmpty) {
      return false;
    }
    for (var grade in semester.grades) {
      if (customGpaSelected[grade.id] != true) {
        return false;
      }
    }
    return true;
  }

  /// 全选指定学期的所有课程
  void selectAllGradesInSemester(int semesterIndex) {
    if (semesterIndex < 0 || semesterIndex >= semestersWithGrades.length) {
      return;
    }
    final semester = semestersWithGrades[semesterIndex];
    for (var grade in semester.grades) {
      customGpaSelected[grade.id] = true;
    }
    refreshCustomGpa();
  }

  /// 清空指定学期的所有课程选择
  void clearGradesInSemester(int semesterIndex) {
    if (semesterIndex < 0 || semesterIndex >= semestersWithGrades.length) {
      return;
    }
    final semester = semestersWithGrades[semesterIndex];
    for (var grade in semester.grades) {
      customGpaSelected[grade.id] = false;
    }
    refreshCustomGpa();
  }

  /// 切换指定学期的选择状态：如果已全选则清空，否则全选
  void toggleSemesterSelection(int semesterIndex) {
    if (isSemesterAllSelected(semesterIndex)) {
      clearGradesInSemester(semesterIndex);
    } else {
      selectAllGradesInSemester(semesterIndex);
    }
  }
}
