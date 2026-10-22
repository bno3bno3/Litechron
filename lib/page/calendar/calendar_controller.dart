import 'package:litechron/model/task.dart';
import 'package:litechron/utils/task_updates.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/semester.dart';

enum CalendarViewMode {
  calendar,
  schedule,
}

/// 月历只读取绘制标记所需的数据，避免反复复制可编辑的 Period。
class CalendarEventMarker {
  final PeriodType type;
  final int hour;
  final String? colorUid;

  CalendarEventMarker._(Period event)
      : type = event.type,
        hour = event.startTime.hour,
        colorUid = event.fromFromUid ?? event.fromUid;
}

class _CalendarDayEvents {
  final List<Period> periods;
  late final markers = List<CalendarEventMarker>.unmodifiable(
      periods.map(CalendarEventMarker._));

  _CalendarDayEvents(this.periods);
}

class CalendarController extends GetxController {
  final selectedDay = DateTime.now().obs;
  final focusedDay = DateTime.now().obs;
  final calendarFormat = CalendarFormat.month.obs;
  final events = <DateTime, List<Period>>{}.obs;
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');
  final viewMode = CalendarViewMode.calendar.obs;
  Worker? _scholarWorker;
  Worker? _taskWorker;
  List<Task> _fixedTasks = [];
  // 容纳相邻三个月的日期页，并限制长期翻月产生的缓存。
  static const _maxCachedDays = 128;
  final _dayEvents = <DateTime, _CalendarDayEvents>{};

  static List<String> numToChinese = ['一', '二', '三', '四', '五', '六', '七', '八'];

  String dayDescription(DateTime day) {
    var semester = scholar.value.semesters.firstWhereOrNull(
        (e) => !day.isBefore(e.firstDay) && !day.isAfter(e.lastDay));
    if (semester == null) return '考试周/假期';

    var toFirstWeek = day.difference(semester.firstDay).inDays ~/ 7;
    if (toFirstWeek < 8) {
      return '${semester.name[9]}${numToChinese[toFirstWeek]}周';
    }
    var toLastWeek = 7 - semester.lastDay.difference(day).inDays ~/ 7;
    if (toLastWeek < 8) {
      return '${semester.name[10]}${numToChinese[toLastWeek]}周';
    }
    return '考试周/假期';
  }

  @override
  void onInit() {
    _refreshFixedTasks();
    refreshEvents();
    _scholarWorker = ever(scholar, (callback) => refreshEvents());
    _taskWorker = ever(taskList, (_) {
      if (TaskUpdates.isProgressOnly) return;
      _refreshFixedTasks();
      _dayEvents.clear();
      events.refresh();
    });
    super.onInit();
  }

  @override
  void onClose() {
    _scholarWorker?.dispose();
    _taskWorker?.dispose();
    _dayEvents.clear();
    super.onClose();
  }

  void refreshEvents() {
    final nextEvents = <DateTime, List<Period>>{};
    for (final period in scholar.value.periods) {
      (nextEvents[chopDate(period.startTime)] ??= []).add(period.copyWith());
    }
    for (final periods in nextEvents.values) {
      periods.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    _dayEvents.clear();
    // 先完成索引和排序，再一次性通知，避免暴露空表或未完成的日期。
    events.assignAll(nextEvents);
  }

  void _refreshFixedTasks() {
    _fixedTasks = taskList
        .where((task) =>
            task.type == TaskType.fixed || task.type == TaskType.fixedlegacy)
        .toList(growable: false);
  }

  DateTime chopDate(DateTime day) {
    return DateTime(day.year, day.month, day.day);
  }

  List<Period> getEventsForDay(DateTime day) {
    // 详情/编辑使用独立副本，不能修改缓存或学业模型中的共享对象。
    return _getDayEvents(day).periods.map((event) => event.copyWith()).toList();
  }

  List<CalendarEventMarker> Function(DateTime) get markerLoader {
    // TableCalendar 延迟调用 eventLoader，依赖必须在父 Obx 构建时登记。
    events();
    return getMarkersForDay;
  }

  List<CalendarEventMarker> getMarkersForDay(DateTime day) =>
      _getDayEvents(day).markers;

  _CalendarDayEvents _getDayEvents(DateTime day) {
    final chop = chopDate(day);
    // 命中缓存时也读取 Rx，保证选中日期的详情会随数据变动而刷新。
    final academicEvents = events[chop];
    final cached = _dayEvents.remove(chop);
    if (cached != null) {
      _dayEvents[chop] = cached;
      return cached;
    }
    final eventsOfDay = <Period>[...?academicEvents];
    for (final task in _fixedTasks) {
      eventsOfDay.addAll(task.getPeriodOfDay(chop));
    }
    eventsOfDay.sort((a, b) => a.startTime.compareTo(b.startTime));
    final result = _CalendarDayEvents(eventsOfDay);
    _dayEvents[chop] = result;
    if (_dayEvents.length > _maxCachedDays) {
      _dayEvents.remove(_dayEvents.keys.first);
    }
    return result;
  }

  void toggleViewMode() {
    viewMode.value = viewMode.value == CalendarViewMode.calendar
        ? CalendarViewMode.schedule
        : CalendarViewMode.calendar;
  }

  Semester? getCurrentSemester() {
    final now = DateTime.now();
    return scholar.value.semesters.firstWhereOrNull(
      (e) => !now.isBefore(e.firstDay) && !now.isAfter(e.lastDay),
    );
  }

  bool isFirstHalfSemester(Semester semester) {
    final now = DateTime.now();
    final toFirstWeek = now.difference(semester.firstDay).inDays ~/ 7;
    return toFirstWeek < 8;
  }

  String getCurrentSemesterDisplayName() {
    final semester = getCurrentSemester();
    if (semester == null) return '无学期信息';

    final isFirstHalf = isFirstHalfSemester(semester);
    final semesterName =
        '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}';
    final halfName =
        isFirstHalf ? semester.firstHalfName : semester.secondHalfName;
    return '$semesterName $halfName学期';
  }
}
