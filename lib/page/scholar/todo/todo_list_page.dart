import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:litechron/design/animate_button.dart';
import 'package:litechron/design/custom_colors.dart';
import 'package:litechron/design/persistent_headers.dart';
import 'package:litechron/design/round_rectangle_card.dart';
import 'package:litechron/model/todo.dart';

import '../scholar_controller.dart';
import 'todo_filter.dart';

class TodoListPage extends StatefulWidget {
  const TodoListPage({required this.initialFilter, super.key});

  final TodoFilter initialFilter;

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> {
  final _controller = Get.find<ScholarController>();
  late TodoFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  Widget _filters(BuildContext context) => RoundRectangleCard(
        animate: false,
        child: Row(children: [
          for (final filter in TodoFilter.values) ...[
            if (filter != TodoFilter.all) const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                button: true,
                selected: _filter == filter,
                child: AnimateButton(
                  text: filter.label,
                  backgroundColor: _filter == filter
                      ? CustomCupertinoDynamicColors.magenta
                      : CupertinoColors.systemFill,
                  foregroundColor: _filter == filter
                      ? null
                      : CupertinoDynamicColor.resolve(
                          CupertinoColors.label, context),
                  onTap: () => setState(() => _filter = filter),
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _item(BuildContext context, Todo todo, DateTime now) =>
      RoundRectangleCard(
        animate: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(todo.name,
                style: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(todo.course, style: _secondaryText(context)),
            const SizedBox(height: 4),
            Text(_deadline(todo.endTime, now), style: _secondaryText(context)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        child: Obx(() {
          final now = _controller.todoNow;
          final items = _controller.todosFor(_filter);
          return CustomScrollView(
            slivers: [
              // 共用标题高度固定，给中文字体的行高留余量；卡片保留完整缩放。
              MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: const LitechronSliverTextHeader(subtitle: '作业明细')),
              SliverPinnedToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.5,
                    child: Builder(builder: _filters),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('共 ${items.length} 项 · 按截止时间排序',
                          style: _secondaryText(context)),
                      const SizedBox(height: 4),
                      Text(_filter.scope, style: _secondaryText(context)),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 32),
                    child: Text(_filter.emptyMessage,
                        textAlign: TextAlign.center,
                        style: _secondaryText(context)),
                  ),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    child: _item(context, items[index], now),
                  ),
                  childCount: items.length,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 24),
              ),
            ],
          );
        }),
      );
}

TextStyle _secondaryText(BuildContext context) => TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondaryLabel, context),
    );

String _deadline(DateTime? deadline, DateTime now) {
  if (deadline == null) return '无截止日期';
  final local = deadline.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final date =
      '${local.year}.${twoDigits(local.month)}.${twoDigits(local.day)}';
  final time = '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  return '截止 $date $time${deadline.isBefore(now) ? ' · 已截止' : ''}';
}
