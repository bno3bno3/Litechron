import 'package:litechron/design/custom_decoration.dart';
import 'package:litechron/page/flow/flow_controller.dart';
import 'package:litechron/page/task/task_controller.dart';
import 'package:litechron/utils/utils.dart';
import 'package:litechron/design/sub_title.dart';
import 'package:litechron/design/round_rectangle_card.dart';
import 'package:litechron/design/custom_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/model/period.dart';
import 'task_edit_page.dart';
import 'task_swipe_card.dart';
import 'dart:async';
import 'package:get/get.dart';

class TaskPage extends StatefulWidget {
  const TaskPage({super.key, this.isActive});

  final ValueListenable<bool>? isActive;

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final _taskController = Get.put(TaskController());
  final _flowController = Get.put(FlowController());
  final _swipeController = TaskSwipeController();
  late final Worker _taskChanges;
  Task? _activeTask;
  TaskType? _activeType;
  bool? _activeCompleted;

  @override
  void initState() {
    super.initState();
    _swipeController.addListener(_rememberActiveTask);
    widget.isActive?.addListener(_onVisibilityChanged);
    _taskChanges = ever(_taskController.taskList, (_) {
      final uid = _swipeController.value;
      if (uid == null) return;
      final task =
          _taskController.taskList.firstWhereOrNull((task) => task.uid == uid);
      if (task == null ||
          !identical(task, _activeTask) ||
          task.type != _activeType ||
          (task.status == TaskStatus.completed) != _activeCompleted) {
        _swipeController.close();
      }
    });
  }

  void _rememberActiveTask() {
    _activeTask = _taskController.taskList
        .firstWhereOrNull((task) => task.uid == _swipeController.value);
    _activeType = _activeTask?.type;
    _activeCompleted = _activeTask?.status == TaskStatus.completed;
  }

  void _onVisibilityChanged() {
    if (widget.isActive?.value == false) _swipeController.close();
  }

  @override
  void didUpdateWidget(TaskPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      oldWidget.isActive?.removeListener(_onVisibilityChanged);
      widget.isActive?.addListener(_onVisibilityChanged);
      _onVisibilityChanged();
    }
  }

  @override
  void dispose() {
    _taskChanges.dispose();
    widget.isActive?.removeListener(_onVisibilityChanged);
    _swipeController.dispose();
    super.dispose();
  }

  void _onSwipeAction(String uid, {required bool delete}) {
    final changed = delete
        ? _taskController.deleteTask(uid)
        : _taskController.toggleTaskCompletion(uid);
    if (!changed) return;
    _flowController.removeFlowInFlowList();
    final now = DateTime.now();
    _flowController.generateNewFlowList(
        DateTime(now.year, now.month, now.day, now.hour, now.minute));
    _taskController.taskList.refresh();
  }

  String deadlineProgress(Task deadline) {
    return '${(deadline.getProgress() * 100).toInt()}% 已完成：预期 ${durationToString(deadline.timeNeeded)}，还要 ${durationToString(deadline.timeNeeded <= deadline.timeSpent ? Duration.zero : (deadline.timeNeeded - deadline.timeSpent))}';
  }

  Future<void> showCardDialog(BuildContext context, Task deadline) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(
            '${deadline.summary}：${deadline.type == TaskType.deadline ? deadlineStatusName[deadline.status]! : deadline.type == TaskType.fixed ? deadlineTypeName[TaskType.fixed] : ''}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (deadline.type == TaskType.fixed) ...[
                    Text(
                      '开始于 ${toStringHumanReadable(deadline.startTime)}',
                    ),
                    Text(
                      '结束于 ${toStringHumanReadable(deadline.endTime)}',
                    ),
                  ],
                  if (deadline.type == TaskType.deadline) ...[
                    Text(
                      '截止于 ${toStringHumanReadable(deadline.endTime)}${deadline.endTime.isBefore(DateTime.now()) ? ' - 已过期' : ''}',
                    ),
                    Text(
                      deadlineProgress(deadline),
                    ),
                  ],
                  if (deadline.location.isNotEmpty) ...[
                    Text(
                      '地点：${deadline.location}',
                    ),
                  ],
                  if (deadline.description.isNotEmpty) ...[
                    Text(
                      '说明：${deadline.description}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
            if (deadline.type == TaskType.deadline &&
                deadline.timeSpent < deadline.timeNeeded)
              CupertinoDialogAction(
                onPressed: () {
                  if (deadline.status != TaskStatus.completed) {
                    deadline.status = TaskStatus.completed;
                  } else {
                    deadline.forceRefreshStatus();
                  }
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                  Navigator.of(context).pop();
                },
                child: Text(
                    '标记为${deadline.status == TaskStatus.completed ? '未' : ''}完成'),
              ),
            if (deadline.type == TaskType.deadline &&
                (deadline.status == TaskStatus.running ||
                    deadline.status == TaskStatus.suspended))
              CupertinoDialogAction(
                onPressed: () {
                  if (deadline.status == TaskStatus.running) {
                    deadline.status = TaskStatus.suspended;
                  } else {
                    deadline.status = TaskStatus.running;
                  }
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                  Navigator.of(context).pop();
                },
                child:
                    Text(deadline.status == TaskStatus.running ? '暂停' : '继续'),
              ),
            if (deadline.type == TaskType.deadline ||
                deadline.type == TaskType.fixed)
              CupertinoDialogAction(
                onPressed: () async {
                  Navigator.of(context).pop();
                  Task res = await showCupertinoModalPopup(
                        context: context,
                        builder: (BuildContext context) {
                          return TaskEditPage(deadline);
                        },
                      ) ??
                      deadline;
                  bool needUpdate = deadline.differentForFlow(res);
                  deadline.copy(res);
                  _taskController.updateDeadlineList();
                  if (needUpdate) {
                    _taskController.updateDeadlineListTime();
                  }
                  _taskController.taskList.refresh();
                  // 仅改 summary 等字段时 updateDeadlineList 检测不到变化，需显式落盘
                  _taskController.saveDeadlineListToDb();
                },
                child: const Text('编辑'),
              ),
            if (deadline.type == TaskType.fixedlegacy)
              CupertinoDialogAction(
                onPressed: () async {
                  Navigator.of(context).pop();
                  deadline.status = TaskStatus.deleted;
                  _taskController.updateDeadlineList();
                  _taskController.taskList.refresh();
                },
                child: const Text('删除'),
              ),
          ],
        );
      },
    );
  }

  Future<void> newDeadline(context) async {
    DateTime time = DateTime.now();
    Task? deadline = Task(
      endTime: time,
      startTime: time,
      repeatEndsTime: time,
    );
    deadline.reset();
    Task? res = await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return TaskEditPage(deadline);
      },
    );
    if (res != null && res.status != TaskStatus.deleted) {
      _taskController.taskList.add(res);
      _taskController.updateDeadlineList();
      _taskController.updateDeadlineListTime();
      // 重新规划
      _flowController.removeFlowInFlowList();
      DateTime now = DateTime.now();
      DateTime startsAt =
          DateTime(now.year, now.month, now.day, now.hour, now.minute);
      _flowController.generateNewFlowList(startsAt);
      _taskController.taskList.refresh();
    }
  }

  Widget createCard(context, Task deadline, Color color, String? title) {
    double progress = deadline.getProgress();

    return Column(
      children: [
        title == null
            ? const SizedBox(height: 0)
            : SubtitleRow(subtitle: title),
        TaskSwipeCard(
          key: ValueKey(deadline.uid),
          uid: deadline.uid,
          taskLabel: deadline.summary,
          controller: _swipeController,
          isCompleted: deadline.status == TaskStatus.completed,
          onDelete: () => _onSwipeAction(deadline.uid, delete: true),
          onToggleComplete: deadline.type == TaskType.deadline
              ? () => _onSwipeAction(deadline.uid, delete: false)
              : null,
          onTap: () async {
            // 直接导航到编辑页面
            Task? res = await Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute(
                builder: (context) => TaskEditPage(deadline),
              ),
            );
            if (res != null && res.status != TaskStatus.deleted) {
              deadline.copy(res);
              _taskController.updateDeadlineList();
              _taskController.updateDeadlineListTime();
              // 重新规划
              _flowController.removeFlowInFlowList();
              DateTime now = DateTime.now();
              DateTime startsAt =
                  DateTime(now.year, now.month, now.day, now.hour, now.minute);
              _flowController.generateNewFlowList(startsAt);
              _taskController.taskList.refresh();
            }
          },
          child: RoundRectangleCard(
            animate: false,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12.0,
                        height: 12.0,
                        decoration: customDecoration(
                          color: color,
                          shape: periodTypeShape[PeriodType.user]!,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                          flex: 4,
                          child: Text(deadline.summary,
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    overflow: TextOverflow.ellipsis,
                                  ))),
                      const Spacer(),
                      // 固定日程的状态随时间翻转；taskList 不再每秒通知，改由 timeNow 驱动
                      Obx(() {
                        final now = _flowController.timeNow.value;
                        return Text(
                            deadline.type == TaskType.deadline
                                ? deadlineStatusName[deadline.status]!
                                : (now.isBefore(deadline.startTime)
                                    ? '未开始'
                                    : (!now.isBefore(deadline.endTime)
                                        ? '已结束'
                                        : '进行中')),
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  overflow: TextOverflow.ellipsis,
                                ));
                      }),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.time_solid,
                        size: 14,
                        color: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .color!
                            .withValues(alpha: 0.5),
                      ),
                      Expanded(
                        child: Text(
                          deadline.type == TaskType.fixed
                              ? ' 开始于：${toStringHumanReadable(deadline.startTime)}'
                              : ' 截止于：${toStringHumanReadable(deadline.endTime)}${deadline.endTime.isBefore(DateTime.now()) ? ' - 已过期' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .color!
                                .withValues(alpha: 0.75),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (deadline.type == TaskType.fixed) ...[
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.time,
                          size: 14,
                          color: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .color!
                              .withValues(alpha: 0.5),
                        ),
                        Expanded(
                          child: Text(
                            ' 结束于：${toStringHumanReadable(deadline.endTime)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .color!
                                  .withValues(alpha: 0.75),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (deadline.location.isNotEmpty) ...[
                    Row(children: [
                      Icon(
                        CupertinoIcons.location_solid,
                        size: 14,
                        color: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .color!
                            .withValues(alpha: 0.5),
                      ),
                      Expanded(
                          child: Text(' 地点：${deadline.location}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .color!
                                    .withValues(alpha: 0.75),
                                overflow: TextOverflow.ellipsis,
                              )))
                    ]),
                  ],
                  if (deadline.type == TaskType.deadline)
                    Row(children: [
                      Icon(
                        CupertinoIcons.play_fill,
                        size: 14,
                        color: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .color!
                            .withValues(alpha: 0.5),
                      ),
                      Expanded(
                          child: Text(deadlineProgress(deadline),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .color!
                                    .withValues(alpha: 0.75),
                                overflow: TextOverflow.ellipsis,
                              ))),
                    ]),
                  if (deadline.type == TaskType.fixed ||
                      deadline.status == TaskStatus.running) ...[
                    const SizedBox(height: 8.0),
                    // 固定日程的进度随时间前进，订阅 timeNow 以便每秒刷新
                    Obx(() {
                      final _ = _flowController.timeNow.value;
                      return LinearProgressIndicator(
                        value: deadline.getProgress(),
                        backgroundColor: CupertinoDynamicColor.resolve(
                            CupertinoColors.separator, context),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      );
                    }),
                  ],
                  if (deadline.type == TaskType.deadline &&
                      deadline.status == TaskStatus.suspended) ...[
                    const SizedBox(height: 8.0),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: CupertinoDynamicColor.resolve(
                          CupertinoColors.separator, context),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ],
                  if (deadline.type == TaskType.deadline &&
                      deadline.status == TaskStatus.completed) ...[
                    const SizedBox(height: 8.0),
                    LinearProgressIndicator(
                      value: 1,
                      backgroundColor: CupertinoDynamicColor.resolve(
                          CupertinoColors.separator, context),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ],
                  if (deadline.type == TaskType.deadline &&
                      deadline.status == TaskStatus.failed) ...[
                    const SizedBox(height: 8.0),
                    LinearProgressIndicator(
                      value: 0,
                      backgroundColor: CupertinoDynamicColor.resolve(
                          CupertinoColors.separator, context),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _taskSliver(List<Task> tasks, String title) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final task = tasks[index];
          return Padding(
            key: ValueKey(task.uid),
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : 5,
              bottom: 5,
              left: 16,
              right: 16,
            ),
            child: createCard(context, task, UidColors.colorFromUid(task.uid),
                index == 0 ? title : null),
          );
        },
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = tasks.indexWhere((task) => task.uid == key.value);
          return index < 0 ? null : index;
        },
        childCount: tasks.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TaskSwipeRegion(
      controller: _swipeController,
      child: CupertinoPageScaffold(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('任务'),
                border: null,
                stretch: true,
                trailing: // Two buttons in the nav bar.
                    Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Icon(
                        CupertinoIcons.add_circled,
                        semanticLabel: 'Add',
                      ),
                      onPressed: () async {
                        _swipeController.close();
                        await newDeadline(context);
                        _taskController.updateDeadlineList();
                        _taskController.taskList.refresh();
                      },
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Icon(
                        CupertinoIcons.ellipsis_circle,
                        semanticLabel: 'More',
                      ),
                      onPressed: () async {
                        _swipeController.close();
                        await showCupertinoModalPopup(
                          context: context,
                          builder: (BuildContext context) =>
                              CupertinoActionSheet(
                            actions: <Widget>[
                              CupertinoActionSheetAction(
                                child: const Text('删除已完成任务'),
                                onPressed: () async {
                                  _taskController
                                      .removeCompletedDeadline(context);
                                  _taskController.updateDeadlineList();
                                  _taskController.taskList.refresh();
                                  Navigator.of(context).pop();
                                },
                              ),
                              CupertinoActionSheetAction(
                                child: const Text('删除已过期任务'),
                                onPressed: () async {
                                  _taskController.removeFailedDeadline(context);
                                  _taskController.updateDeadlineList();
                                  _taskController.taskList.refresh();
                                  Navigator.of(context).pop();
                                },
                              ),
                              CupertinoActionSheetAction(
                                child: const Text('暂停所有任务'),
                                onPressed: () {
                                  if (_taskController
                                          .suspendAllDeadline(context) >
                                      0) {
                                    _flowController.removeFlowInFlowList();
                                    _taskController.updateDeadlineListTime();
                                    _taskController.taskList.refresh();
                                  }
                                  Navigator.of(context).pop();
                                },
                              ),
                              CupertinoActionSheetAction(
                                child: const Text('继续所有任务'),
                                onPressed: () {
                                  if (_taskController
                                          .continueAllDeadline(context) >
                                      0) {
                                    _flowController.removeFlowInFlowList();
                                    _taskController.updateDeadlineListTime();
                                    _taskController.taskList.refresh();
                                  }
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                            cancelButton: CupertinoActionSheetAction(
                              isDefaultAction: true,
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('取消'),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Obx(() => SliverToBoxAdapter(
                    child: _taskController.todoDeadlineList.isEmpty &&
                            _taskController.doneDeadlineList.isEmpty &&
                            _taskController.fixedDeadlineList.isEmpty
                        ? SizedBox(
                            height: 500,
                            child: Column(
                              children: [
                                const Spacer(),
                                Text(
                                  '没有任务',
                                  style: CupertinoTheme.of(context)
                                      .textTheme
                                      .textStyle,
                                  textAlign: TextAlign.center,
                                ),
                                const Spacer(),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  )),
              Obx(
                () => _taskSliver(_taskController.todoDeadlineList, '待办'),
              ),
              Obx(
                () => _taskSliver(_taskController.doneDeadlineList, '已完成'),
              ),
              Obx(
                () => _taskSliver(_taskController.fixedDeadlineList, '日程列表'),
              ),
              SliverToBoxAdapter(
                child: Container(
                  height: 100,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskPageColors {
  static const List<CupertinoDynamicColor> taskMarkColors = [
    spring,
    summer,
    winter,
    violet,
    sakura,
    cyan,
    magenta,
    peach,
    okGreen,
  ];

  static const CupertinoDynamicColor spring =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 255, 226, 1.0),
    darkColor: Color.fromRGBO(147, 251, 56, 1.0),
  );

  static const CupertinoDynamicColor summer =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 218, 238, 1.0),
    darkColor: Color.fromRGBO(255, 25, 69, 1.0),
  );

  static const CupertinoDynamicColor autumn =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 234, 230, 1.0),
    darkColor: Color.fromRGBO(255, 101, 56, 1.0),
  );

  static const CupertinoDynamicColor winter =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(226, 239, 255, 1.0),
    darkColor: Color.fromRGBO(0, 183, 251, 1.0),
  );

  static const CupertinoDynamicColor violet =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 229, 255, 1.0),
    darkColor: Color.fromRGBO(151, 131, 216, 1.0),
  );

  static const CupertinoDynamicColor sakura =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 226, 255, 1.0),
    darkColor: Color.fromRGBO(218, 130, 217, 1.0),
  );

  static const CupertinoDynamicColor sand =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 246, 211, 1.0),
    darkColor: Color.fromRGBO(252, 222, 59, 1.0),
  );

  static const CupertinoDynamicColor cyan =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(218, 234, 255, 1.0),
    darkColor: Color.fromRGBO(0, 140, 255, 1.0),
  );

  static const CupertinoDynamicColor magenta =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 229, 255, 1.0),
    darkColor: Color.fromRGBO(238, 55, 161, 1.0),
  );

  static const CupertinoDynamicColor peach =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 235, 226, 1.0),
    darkColor: Color.fromRGBO(233, 114, 70, 1.0),
  );

  static const CupertinoDynamicColor okGreen =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 255, 226, 1.0),
    darkColor: Color.fromRGBO(63, 222, 23, 1.0),
  );
}
