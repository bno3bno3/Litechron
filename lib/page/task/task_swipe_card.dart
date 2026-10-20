import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

/// Transient UI state shared by all cards on the task page.
class TaskSwipeController extends ValueNotifier<String?> {
  TaskSwipeController() : super(null);

  void close() => value = null;
}

/// Closes revealed actions on a background tap or a vertical scroll, without
/// intercepting a horizontal drag on another card.
class TaskSwipeRegion extends StatelessWidget {
  const TaskSwipeRegion({
    super.key,
    required this.controller,
    required this.child,
  });

  final TaskSwipeController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: controller.close,
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) controller.close();
          return false;
        },
        child: child,
      ),
    );
  }
}

/// A bounded reveal gesture. Dragging never invokes a task action.
class TaskSwipeCard extends StatefulWidget {
  const TaskSwipeCard({
    super.key,
    required this.uid,
    required this.taskLabel,
    required this.controller,
    required this.child,
    required this.onTap,
    required this.onDelete,
    this.onToggleComplete,
    this.isCompleted = false,
  });

  final String uid;
  final String taskLabel;
  final TaskSwipeController controller;
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onToggleComplete;
  final bool isCompleted;

  @override
  State<TaskSwipeCard> createState() => _TaskSwipeCardState();
}

class _TaskSwipeCardState extends State<TaskSwipeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset;
  bool _dragging = false;
  bool _actionTaken = false;
  int _dragSide = 0;
  double _deleteWidth = 80;
  double _completeWidth = 80;

  @override
  void initState() {
    super.initState();
    _offset = AnimationController.unbounded(vsync: this)
      ..addListener(_rebuild)
      ..addStatusListener((_) => _rebuild());
    widget.controller.addListener(_onActiveCardChanged);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(TaskSwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onActiveCardChanged);
      widget.controller.addListener(_onActiveCardChanged);
    }
    if (oldWidget.uid != widget.uid ||
        oldWidget.controller != widget.controller ||
        oldWidget.isCompleted != widget.isCompleted ||
        (oldWidget.onToggleComplete == null) !=
            (widget.onToggleComplete == null)) {
      _dragging = false;
      _offset.value = 0;
      _actionTaken = false;
      _closeAfterBuild(oldWidget.uid, oldWidget.controller);
    }
  }

  void _closeAfterBuild(String uid, TaskSwipeController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.value == uid) controller.close();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onActiveCardChanged);
    _offset.dispose();
    super.dispose();
  }

  void _onActiveCardChanged() {
    if (widget.controller.value != widget.uid) {
      _dragging = false;
      _settle(0);
    }
  }

  void _settle(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _offset.value = target;
    } else {
      _offset.animateTo(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void _onDragStart(DragStartDetails details) {
    _offset.stop();
    _dragSide = _offset.value.sign.toInt();
    _dragging = true;
    _actionTaken = false;
    widget.controller.value = widget.uid;
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final delta = details.primaryDelta!;
    if (_dragSide == 0) _dragSide = delta.sign.toInt();
    // A reverse drag can close the current action, but cannot open its opposite.
    final min = _dragSide < 0 ? -_deleteWidth : 0.0;
    final max =
        _dragSide > 0 && widget.onToggleComplete != null ? _completeWidth : 0.0;
    _offset.value = (_offset.value + delta).clamp(min, max);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final width = _dragSide < 0 ? _deleteWidth : _completeWidth;
    if (_offset.value.abs() >= width / 2) {
      _settle(_dragSide * width);
    } else {
      widget.controller.close();
    }
    setState(() {});
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    widget.controller.close();
  }

  void _onTap() {
    if (widget.controller.value != null || _offset.value != 0) {
      widget.controller.close();
      _settle(0);
      return;
    }
    widget.onTap();
  }

  bool _canActivate(bool delete) {
    final target = delete ? -_deleteWidth : _completeWidth;
    return !_dragging &&
        !_offset.isAnimating &&
        !_actionTaken &&
        widget.controller.value == widget.uid &&
        (_offset.value - target).abs() < 0.01;
  }

  void _activate(bool delete) {
    if (!_canActivate(delete)) return;
    _actionTaken = true;
    widget.controller.close();
    (delete ? widget.onDelete : widget.onToggleComplete!)();
  }

  double _buttonWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _buttonStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = math.max(80.0, painter.width + 32);
    painter.dispose();
    return width;
  }

  static const _buttonStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: CupertinoColors.white,
  );

  Widget _action(bool delete) {
    final enabled = _canActivate(delete);
    final label = delete ? '删除' : (widget.isCompleted ? '恢复' : '完成');
    final semanticLabel = delete
        ? '删除任务：${widget.taskLabel}'
        : '${widget.isCompleted ? '恢复未完成' : '标记完成'}：${widget.taskLabel}';
    final color = delete
        ? CupertinoColors.systemRed
        : (widget.isCompleted
            ? CupertinoColors.systemOrange
            : CupertinoColors.systemGreen);
    return ExcludeSemantics(
      excluding: !enabled,
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        onTap: enabled ? () => _activate(delete) : null,
        child: IgnorePointer(
          ignoring: !enabled,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.zero,
            color: CupertinoDynamicColor.resolve(color, context),
            onPressed: () => _activate(delete),
            child: Text(label, style: _buttonStyle),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _deleteWidth = _buttonWidth('删除');
    _completeWidth = _buttonWidth(widget.isCompleted ? '恢复' : '完成');
    final offset = _offset.value;
    final card = Stack(
      children: [
        if (offset != 0)
          Positioned(
            top: 0,
            bottom: 0,
            left: offset > 0 ? 0 : null,
            right: offset < 0 ? 0 : null,
            width: offset < 0 ? _deleteWidth : _completeWidth,
            child: _action(offset < 0),
          ),
        Transform.translate(
          offset: Offset(offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            child: widget.child,
          ),
        ),
      ],
    );
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _TaskHorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                _TaskHorizontalDragGestureRecognizer>(
          () => _TaskHorizontalDragGestureRecognizer(),
          (recognizer) => recognizer
            ..gestureSettings = MediaQuery.gestureSettingsOf(context)
            ..dragStartBehavior = DragStartBehavior.down
            ..canSwipeRight =
                (() => widget.onToggleComplete != null || _offset.value < 0)
            ..onStart = _onDragStart
            ..onUpdate = _onDragUpdate
            ..onEnd = _onDragEnd
            ..onCancel = _onDragCancel,
        ),
      },
      // Keep the existing shadow while closed; clip translated content and
      // action backgrounds to the card's outline only during a reveal.
      child: offset == 0
          ? card
          : ClipRRect(borderRadius: BorderRadius.circular(12), child: card),
    );
  }
}

class _TaskHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  late bool Function() canSwipeRight;

  @override
  bool hasSufficientGlobalDistanceToAccept(
      PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    if (!super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind, deviceTouchSlop)) {
      return false;
    }
    // A closed fixed schedule has no leading action. Let the parent PageView
    // handle rightward drags, just as it did before this reveal interaction.
    if (globalDistanceMoved > 0 && !canSwipeRight()) {
      resolve(GestureDisposition.rejected);
      return false;
    }
    return true;
  }
}
