import 'package:litechron/database/database_helper.dart';
import 'package:get/get.dart';
import 'package:litechron/model/grade.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/semester.dart';
import 'package:litechron/page/option/option_controller.dart';

/// 单门课程权重控制器
///
/// 管理推免绩点计算中的单门课程权重覆盖（Map<String, double>，key 为 grade.id）。
/// 无记录的课跟随推免规则：主修课取规则里的主修课权重，其他课为 1。
/// 权重存于 Hive（DatabaseHelper.getWeightedGpa / setWeightedGpa），改动后同步重算派生值。
class WeightedGpaController extends GetxController {
  static const double maxWeight = 2.0;

  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  final _optionController = Get.find<OptionController>(tag: 'optionController');
  final RxMap<String, double> weightedMap = RxMap<String, double>();
  final semesterIndex = 0.obs;
  final showAllSemesters = false.obs;
  late RxList<Semester> semestersWithGrades;

  @override
  void onInit() {
    super.onInit();
    weightedMap.value = _db.getWeightedGpa();
    semestersWithGrades = scholar.value.semesters
        .where((element) => element.grades.isNotEmpty)
        .toList()
        .obs;
    ever(scholar, (callback) => refreshSemesters());
  }

  void refreshSemesters() {
    semestersWithGrades.value = scholar.value.semesters
        .where((element) => element.grades.isNotEmpty)
        .toList();
    semestersWithGrades.refresh();
  }

  /// 该课的覆盖权重；无覆盖返回 null
  double? getOverride(String gradeId) => weightedMap[gradeId];

  /// 无覆盖时按推免规则生效的权重，作为输入框占位符
  double getDefaultWeight(Grade grade) => scholar.value.isMajor(grade)
      ? _optionController.recommendGpaRule.value.majorWeight
      : 1.0;

  /// 设置覆盖权重；传 null 清除覆盖、恢复跟随规则。范围 0 到 2，越界静默裁剪
  void setWeight(String gradeId, double? weight) {
    if (weight == null || weight.isNaN) {
      weightedMap.remove(gradeId);
    } else {
      weightedMap[gradeId] = weight.clamp(0.0, maxWeight);
    }
    refreshWeightedGpa();
  }

  void refreshWeightedGpa() {
    _db.setWeightedGpa(Map<String, double>.from(weightedMap));
    // 单门权重参与推免绩点计算，同步重算派生值
    scholar.value.recalculateDerivedGpa();
    scholar.refresh();
  }

  List<Grade> getAllGrades() {
    return scholar.value.grades.values.expand((g) => g).toList();
  }

  /// 当前筛选范围的成绩：全部学期或当前选中学期
  List<Grade> getCurrentSemesterGrades() {
    if (showAllSemesters.value) {
      return getAllGrades();
    }
    if (semestersWithGrades.isEmpty ||
        semesterIndex.value >= semestersWithGrades.length) {
      return [];
    }
    return semestersWithGrades[semesterIndex.value].grades;
  }
}
