import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/utils/task_updates.dart';

class TaskController extends GetxController with WidgetsBindingObserver {
  TaskController({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');
  final taskListLastUpdate = Get.find<Rx<DateTime>>(tag: 'taskListLastUpdate');
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  Timer? _timer;
  Worker? _taskWorker;
  Worker? _updateTimeWorker;
  bool _checking = false;
  bool _updateQueued = false;
  bool _paused = false;

  List<Task> get todoDeadlineList => taskList
      .where((element) => (element.type == TaskType.deadline &&
          (element.status == TaskStatus.running ||
              element.status == TaskStatus.suspended ||
              element.status == TaskStatus.failed)))
      .toList();

  List<Task> get doneDeadlineList => taskList
      .where((element) => (element.type == TaskType.deadline &&
          element.status == TaskStatus.completed))
      .toList();

  List<Task> get fixedDeadlineList =>
      taskList.where((element) => (element.type == TaskType.fixed)).toList();

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    _taskWorker = ever(taskList, (_) {
      if (!TaskUpdates.isProgressOnly) _queueUpdate();
    });
    _updateTimeWorker = ever(taskListLastUpdate, (_) => _queueUpdate());
    updateDeadlineList();
    super.onInit();
  }

  void _queueUpdate() {
    if (_checking || _updateQueued || _paused || isClosed) return;
    _updateQueued = true;
    scheduleMicrotask(() {
      if (!_updateQueued || isClosed) return;
      _updateQueued = false;
      updateDeadlineList();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      updateDeadlineList();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _paused = true;
      _updateQueued = false;
      _timer?.cancel();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _paused = true;
    _updateQueued = false;
    _timer?.cancel();
    _taskWorker?.dispose();
    _updateTimeWorker?.dispose();
    super.onClose();
  }

  Future<void> saveDeadlineListToDb() async {
    await _db.setTaskList(taskList);
    await _db.setTaskListUpdateTime(taskListLastUpdate.value);
  }

  void loadDeadlineListLastUpdate() {
    taskListLastUpdate.value = _db.getTaskListUpdateTime();
  }

  void updateDeadlineListTime() {
    taskListLastUpdate.value = _now();
    // 所有改字段不改列表结构的用户操作（标记完成、暂停/继续等）都经过这里，即时落盘
    saveDeadlineListToDb();
  }

  /// 刷新任务状态（过期判定、固定日程滚动等）。返回是否有数据变化。
  /// 数据变化、时间边界及恢复前台时检查；只在真正有变化时通知 UI 和写库。
  bool updateDeadlineList() {
    if (_checking) return false;
    _checking = true;
    _updateQueued = false;
    try {
      return _updateDeadlineList(_now());
    } finally {
      _checking = false;
    }
  }

  bool _updateDeadlineList(DateTime now) {
    var changed = false;

    if (taskList.any((element) => element.status == TaskStatus.deleted)) {
      taskList.removeWhere((element) => element.status == TaskStatus.deleted);
      changed = true;
    }

    Set<String> existingUid = {};
    List<Task> newDeadlineList = [];
    for (var deadline in taskList) {
      final oldStatus = deadline.status;
      final oldEndTime = deadline.endTime;
      if (deadline.type == TaskType.deadline) {
        if (deadline.timeSpent >= deadline.timeNeeded) {
          deadline.status = TaskStatus.completed;
        } else if (deadline.status != TaskStatus.completed &&
            deadline.endTime.isBefore(now)) {
          deadline.status = TaskStatus.failed;
        }
      } else if (deadline.type == TaskType.fixed) {
        deadline.refreshStatus();
        existingUid.add(deadline.uid);
        while (deadline.endTime.isBefore(now) &&
            deadline.status != TaskStatus.outdated) {
          Task temp = deadline.copyWith(
            summary: '${deadline.summary}（过去日程）',
            type: TaskType.fixedlegacy,
            repeatType: TaskRepeatType.norepeat,
            fromUid: deadline.uid,
          );
          if (deadline.setToNextPeriod()) {
            temp.genUid();
            newDeadlineList.add(temp);
          } else {
            break;
          }
        }
      }
      if (deadline.status != oldStatus || deadline.endTime != oldEndTime) {
        changed = true;
      }
    }
    if (newDeadlineList.isNotEmpty) {
      taskList.addAll(newDeadlineList);
      changed = true;
    }
    if (taskList.any((element) =>
        element.type == TaskType.fixedlegacy &&
        !existingUid.contains(element.fromUid))) {
      taskList.removeWhere((element) =>
          element.type == TaskType.fixedlegacy &&
          !existingUid.contains(element.fromUid));
      changed = true;
    }

    // 视图可能直接 taskList.add 了新任务或改了 endTime，用顺序守卫兜底
    if (!changed) {
      changed = !_isSortedByEndTime();
    }

    if (changed) {
      // sort 无条件通知，兼作纯状态翻转（无 RxList 结构操作）时的 UI 通知
      taskList.sort((a, b) => a.endTime.compareTo(b.endTime));
      saveDeadlineListToDb();
    }
    _scheduleNextUpdate(now);
    return changed;
  }

  void _scheduleNextUpdate(DateTime now) {
    _timer?.cancel();
    if (_paused || isClosed) return;
    DateTime? next;
    for (final task in taskList) {
      final needsExpiry = task.type == TaskType.deadline &&
          task.status != TaskStatus.completed &&
          task.status != TaskStatus.failed;
      final needsRollover =
          task.type == TaskType.fixed && task.status != TaskStatus.outdated;
      if (!needsExpiry && !needsRollover) continue;
      // endTime 此刻仍算有效；越过边界后才失败或滚动，与原判定一致。
      final boundary = task.endTime.add(const Duration(microseconds: 1));
      if (boundary.isAfter(now) && (next == null || boundary.isBefore(next))) {
        next = boundary;
      }
    }
    if (next != null) {
      _timer = Timer(next.difference(now), updateDeadlineList);
    }
  }

  bool _isSortedByEndTime() {
    for (var i = 1; i < taskList.length; i++) {
      if (taskList[i - 1].endTime.isAfter(taskList[i].endTime)) {
        return false;
      }
    }
    return true;
  }

  bool deleteTask(String uid) {
    final task = taskList.firstWhereOrNull((task) => task.uid == uid);
    if (task == null || task.status == TaskStatus.deleted) return false;
    task.status = TaskStatus.deleted;
    updateDeadlineList();
    updateDeadlineListTime();
    return true;
  }

  bool toggleTaskCompletion(String uid) {
    final task = taskList.firstWhereOrNull((task) => task.uid == uid);
    if (task == null ||
        task.type != TaskType.deadline ||
        task.status == TaskStatus.deleted) {
      return false;
    }
    if (task.status == TaskStatus.completed) {
      task.timeSpent = Duration.zero;
      task.forceRefreshStatus();
    } else {
      task.timeSpent = task.timeNeeded;
      task.status = TaskStatus.completed;
    }
    updateDeadlineList();
    updateDeadlineListTime();
    return true;
  }

  void removeCompletedDeadline(context) {
    taskList.removeWhere((element) =>
        element.type == TaskType.deadline &&
        element.status == TaskStatus.completed);
    saveDeadlineListToDb();
  }

  void removeFailedDeadline(context) {
    taskList.removeWhere((element) =>
        element.type == TaskType.deadline &&
        element.status == TaskStatus.failed);
    saveDeadlineListToDb();
  }

  int suspendAllDeadline(context) {
    int count = 0;
    for (var x in taskList) {
      if (x.type == TaskType.deadline && x.status == TaskStatus.running) {
        x.status = TaskStatus.suspended;
        count++;
      }
    }
    return count;
  }

  int continueAllDeadline(context) {
    int count = 0;
    for (var x in taskList) {
      if (x.type == TaskType.deadline && x.status == TaskStatus.suspended) {
        x.status = TaskStatus.running;
        count++;
      }
    }
    return count;
  }
}
