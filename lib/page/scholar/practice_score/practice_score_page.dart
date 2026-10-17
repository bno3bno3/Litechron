import 'dart:async';

import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:litechron/design/animate_button.dart';
import 'package:litechron/design/custom_colors.dart';
import 'package:litechron/design/persistent_headers.dart';
import 'package:litechron/design/refresh_status_indicator.dart';
import 'package:litechron/design/round_rectangle_card.dart';
import 'package:litechron/model/practice_details.dart';
import 'package:litechron/model/practice_score_item.dart';

import 'practice_score_controller.dart';

class PracticeScorePage extends StatefulWidget {
  final int initialCategory;
  const PracticeScorePage({required this.initialCategory, super.key});

  @override
  State<PracticeScorePage> createState() => _PracticeScorePageState();
}

class _PracticeScorePageState extends State<PracticeScorePage> {
  late final String _tag;
  late final PracticeScoreController _controller;
  bool _showingError = false;

  @override
  void initState() {
    super.initState();
    _tag = 'practice-${identityHashCode(this)}';
    _controller = Get.put(
        PracticeScoreController(initialCategory: widget.initialCategory),
        tag: _tag);
  }

  @override
  void dispose() {
    Get.delete<PracticeScoreController>(tag: _tag);
    super.dispose();
  }

  Future<void> _refresh() async {
    final error = await _controller.refreshDetails();
    if (error == null ||
        !mounted ||
        _showingError ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _showingError = true;
    unawaited(showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
              title: const Text('刷新失败'),
              content: Text(error),
              actions: [
                CupertinoDialogAction(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('确定'))
              ],
            )).whenComplete(() => _showingError = false));
  }

  Widget _categories() => RoundRectangleCard(
        animate: false,
        child: Row(children: [
          for (var i = 1; i <= 3; i++) ...[
            if (i > 1) const SizedBox(width: 8),
            Expanded(
                child: AnimateButton(
              text: const ['第二课堂', '第三课堂', '第四课堂'][i - 1],
              backgroundColor: _controller.category.value == i
                  ? CustomCupertinoDynamicColors.peach
                  : CupertinoColors.systemFill,
              foregroundColor: _controller.category.value == i
                  ? null
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
              onTap: () => _controller.selectCategory(i),
            )),
          ]
        ]),
      );

  Widget _summary(BuildContext context) => RoundRectangleCard(
        animate: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('${_controller.categoryName}总分',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .textStyle
                        .copyWith(fontSize: 16, fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            Text(_controller.total.toStringAsFixed(2),
                style: CupertinoTheme.of(context)
                    .textTheme
                    .navTitleTextStyle
                    .copyWith(fontSize: 20)),
          ]),
          const SizedBox(height: 6),
          Text(_controller.updateText, style: _secondaryText(context)),
        ]),
      );

  Widget _filters() => Row(children: [
        for (final value in PracticeFilter.values) ...[
          if (value != PracticeFilter.all) const SizedBox(width: 8),
          Expanded(
              child: AnimateButton(
            text: value == PracticeFilter.all
                ? '全部'
                : '${value == PracticeFilter.aesthetic ? '美育' : '其他'} '
                    '${_controller.details.value.subtotal(value)?.toStringAsFixed(2) ?? '—'}',
            backgroundColor: _controller.filter.value == value
                ? CustomCupertinoDynamicColors.peach
                : CupertinoColors.systemFill,
            foregroundColor: _controller.filter.value == value
                ? null
                : CupertinoDynamicColor.resolve(CupertinoColors.label, context),
            onTap: () => _controller.filter.value = value,
          )),
        ],
      ]);

  Widget _item(BuildContext context, PracticeScoreItem item) =>
      RoundRectangleCard(
        animate: false,
        onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(
            builder: (_) => PracticeScoreDetailPage(item: item))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Text(item.projectName,
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .textStyle
                        .copyWith(fontSize: 16, fontWeight: FontWeight.bold))),
            const SizedBox(width: 20),
            Text(_score(item),
                style: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .copyWith(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: item.statusLabel,
                    style: item.approved
                        ? TextStyle(
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemGreen, context))
                        : null),
                TextSpan(
                    text: ' · ${_date(item.activityStart ?? item.updatedAt)}'),
              ]),
              style: _secondaryText(context)),
          const SizedBox(height: 4),
          Text('${item.projectType} · ${item.qualityType}',
              style: _secondaryText(context, fontSize: 13)),
        ]),
      );

  Widget _notice(String message) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(message,
          textAlign: TextAlign.center, style: _secondaryText(context)));

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            _header('实践明细'),
            SliverPinnedToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Obx(_categories),
            )),
            CupertinoSliverRefreshControl(
              onRefresh: _refresh,
              builder: (context, state, extent, trigger, indicator) => Obx(() =>
                  RefreshStatusIndicator(
                      refreshState: state,
                      pulledExtent: extent,
                      refreshTriggerPullDistance: trigger,
                      refreshIndicatorExtent: indicator,
                      message:
                          _controller.refreshing.value ? '正在更新实践明细' : null)),
            ),
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Obx(() => Column(children: [
                    _summary(context),
                    if (_controller.category.value == 1) ...[
                      const SizedBox(height: 10),
                      _filters(),
                    ],
                  ])),
            )),
            SliverToBoxAdapter(child: Obx(() {
              final details = _controller.details.value;
              if (details.error != null) {
                return _notice('${details.error}\n'
                    '${details.hasCache ? '显示上次结果' : '下拉重试'}');
              }
              if (!details.hasCache) return _notice('下拉加载实践明细');
              if (!details.complete) return _notice('当前仅显示部分记录');
              if (_controller.items.isEmpty) {
                return _notice(_controller.filter.value == PracticeFilter.all
                    ? '暂无${_controller.categoryName}记录'
                    : '暂无对应记录');
              }
              return const SizedBox(height: 5);
            })),
            Obx(() {
              final items = _controller.items;
              return SliverList(
                  delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 5),
                          child: _item(context, items[index])),
                      childCount: items.length));
            }),
            SliverToBoxAdapter(
                child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 24)),
          ],
        ),
      );
}

class PracticeScoreDetailPage extends StatelessWidget {
  final PracticeScoreItem item;
  const PracticeScoreDetailPage({required this.item, super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('项目名称', item.projectName),
      ('获得分数', _score(item)),
      ('课堂类别', item.categoryName),
      ('审核状态', item.statusLabel),
      ('项目类别', item.projectType),
      ('素质类别', item.qualityType),
      ('活动开始时间', _dateTime(item.activityStart)),
      ('活动结束时间', _dateTime(item.activityEnd)),
      ('参与身份或得分原因', item.role ?? '未填写'),
      ('情况说明', item.remark ?? '未填写'),
      ('记录更新时间', _dateTime(item.updatedAt)),
    ];
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(slivers: [
        _header('实践项目详情'),
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: RoundRectangleCard(
              animate: false,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Container(
                                height: 0.5,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.separator, context))),
                      Text(rows[i].$1,
                          style: _secondaryText(context, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(rows[i].$2,
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .copyWith(
                                  color: rows[i].$1 == '审核状态' && item.approved
                                      ? CupertinoDynamicColor.resolve(
                                          CupertinoColors.systemGreen, context)
                                      : null)),
                    ],
                  ])),
        )),
      ]),
    );
  }
}

String _score(PracticeScoreItem item) => item.score.isFinite && item.score >= 0
    ? item.score.toStringAsFixed(2)
    : '—';
String _date(DateTime? date) => date == null
    ? '未填写'
    : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
String _dateTime(DateTime? date) => date == null
    ? '未填写'
    : '${_date(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

// The shared header has a fixed height; cards retain full user text scaling.
Widget _header(String title) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.5, child: LitechronSliverTextHeader(subtitle: title));

TextStyle _secondaryText(BuildContext context,
        {double fontSize = 14}) =>
    TextStyle(
        fontSize: fontSize,
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondaryLabel, context));
