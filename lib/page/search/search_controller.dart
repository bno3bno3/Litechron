import 'package:get/get.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/course.dart';

class SearchPageController extends GetxController {
  final _scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final allCourses = <Course>[].obs;
  Worker? _scholarWorker;

  RxString searchWord = ''.obs;
  List<Course> get courseResult {
    final word = searchWord.value;
    if (word.isEmpty) {
      return <Course>[];
    }
    return allCourses.where((e) => e.name.contains(word)).toList();
  }

  @override
  void onInit() {
    refreshAllCourses();
    _scholarWorker = ever(_scholar, (callback) => refreshAllCourses());
    super.onInit();
  }

  @override
  void onClose() {
    _scholarWorker?.dispose();
    super.onClose();
  }

  void refreshAllCourses() {
    allCourses.assignAll(
        _scholar.value.semesters.expand((semester) => semester.courses.values));
  }
}
