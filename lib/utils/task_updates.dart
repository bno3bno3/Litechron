import 'package:get/get.dart';
import 'package:litechron/model/task.dart';

/// Flow 已通过 updateTimeSpent 更新任务状态；纯进度通知不需要再检查整张任务表。
class TaskUpdates {
  static bool get isProgressOnly => _progressOnly;
  static bool _progressOnly = false;

  static void refreshProgress(RxList<Task> tasks) {
    final previous = _progressOnly;
    _progressOnly = true;
    try {
      // GetX 同步派发通知，界面仍照常接收进度变化。
      tasks.refresh();
    } finally {
      _progressOnly = previous;
    }
  }
}
