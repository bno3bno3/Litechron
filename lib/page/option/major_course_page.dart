import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import 'package:litechron/design/custom_colors.dart';
import 'package:litechron/design/persistent_headers.dart';
import 'package:litechron/design/round_rectangle_card.dart';
import 'package:litechron/design/two_line_card.dart';
import 'package:litechron/model/grade.dart';
import 'option_controller.dart';

/// 主修课程挑选页
///
/// 以成绩单为全集，官网主修标记作为基线；自定义模式下每门课可手动计入或排除，
/// 无手动记录的课跟随官网。官网模式下仅供查看，开关置灰。
class MajorCoursePage extends StatefulWidget {
  const MajorCoursePage({super.key});

  @override
  State<MajorCoursePage> createState() => _MajorCoursePageState();
}

enum _Filter { official, all, included }

class _MajorCoursePageState extends State<MajorCoursePage> {
  final _optionController = Get.find<OptionController>(tag: 'optionController');
  final _searchController = TextEditingController();
  _Filter _filter = _Filter.official;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Grade grade) {
    var scholar = _optionController.scholar.value;
    switch (_filter) {
      case _Filter.official:
        if (!grade.major) return false;
        break;
      case _Filter.included:
        if (!scholar.isMajor(grade)) return false;
        break;
      case _Filter.all:
        break;
    }
    if (_query.isEmpty) return true;
    var q = _query.toLowerCase();
    return grade.name.toLowerCase().contains(q) ||
        grade.id.toLowerCase().contains(q);
  }

  /// 按学期分组后的扁平列表：String 为学期标题，Grade 为课程行
  List<Object> _buildItems() {
    var items = <Object>[];
    for (var semester in _optionController.scholar.value.semesters) {
      var grades = semester.grades.where(_matches).toList();
      if (grades.isEmpty) continue;
      items.add(semester.name);
      items.addAll(grades);
    }
    return items;
  }

  Widget _buildBrief(BuildContext context) {
    return RoundRectangleCard(
      animate: false,
      child: Obx(() {
        var stats = _optionController.scholar.value.effectiveMajorGpaAndCredit;
        return Row(
          children: [
            Expanded(
              child: TwoLineCard(
                title: '主修均绩',
                content: stats[0].toStringAsFixed(2),
                backgroundColor: CustomCupertinoDynamicColors.sakura,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TwoLineCard(
                title: '主修学分',
                content: stats[1].toStringAsFixed(1),
                backgroundColor: CustomCupertinoDynamicColors.sand,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSemesterHeader(BuildContext context, String name) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 12, bottom: 6),
      child: Text(
        name,
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              fontSize: 14,
              color: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .color!
                  .withValues(alpha: 0.5),
            ),
      ),
    );
  }

  Widget _buildGradeRow(BuildContext context, Grade grade) {
    var brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.of(context).platformBrightness;
    var textColor = CupertinoTheme.of(context).textTheme.textStyle.color!;

    return Obx(() {
      var custom = _optionController.useCustomMajor.value;
      // 覆盖表变化会触发 scholar.refresh()，观察 scholar 即可即时刷新
      var included = _optionController.scholar.value.isMajor(grade);

      return GestureDetector(
        onLongPress: custom
            ? () => _optionController.setMajorOverride(grade.id, null)
            : null,
        child: Container(
          padding: const EdgeInsets.only(left: 12, right: 8, bottom: 8, top: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: brightness == Brightness.dark
                ? CupertinoColors.systemFill
                : CupertinoDynamicColor.resolve(
                    CupertinoColors.systemBackground, context),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.1),
                spreadRadius: 0,
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grade.name,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: textColor.withValues(
                                alpha: included ? 1.0 : 0.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                    ),
                    Text(
                      '${grade.realId} / ${grade.credit.toStringAsFixed(1)} 学分${grade.major ? ' · 官网' : ''}',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            color: textColor.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            overflow: TextOverflow.ellipsis,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '${grade.original} / ${grade.fivePoint.toStringAsFixed(1)}',
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.normal,
                      color: textColor.withValues(alpha: included ? 1.0 : 0.5),
                    ),
              ),
              const SizedBox(width: 8),
              CupertinoSwitch(
                value: included,
                onChanged: custom
                    ? (value) =>
                        _optionController.setMajorOverride(grade.id, value)
                    : null,
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    var segmentStyle =
        CupertinoTheme.of(context).textTheme.textStyle.copyWith(fontSize: 14);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          LitechronSliverTextHeader(
            subtitle: '主修课程',
            right: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: GestureDetector(
                onLongPress: _optionController.clearMajorOverrides,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {},
                  child: const Text('长按恢复默认', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Obx(() => CupertinoSlidingSegmentedControl<bool>(
                        children: {
                          false: Text('官网', style: segmentStyle),
                          true: Text('自定义', style: segmentStyle),
                        },
                        groupValue: _optionController.useCustomMajor.value,
                        onValueChanged: (value) =>
                            _optionController.setUseCustomMajor(value!),
                      )),
                  const SizedBox(height: 12),
                  _buildBrief(context),
                  const SizedBox(height: 12),
                  CupertinoSearchTextField(
                    controller: _searchController,
                    placeholder: '课程名或课程代码',
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                  const SizedBox(height: 8),
                  CupertinoSlidingSegmentedControl<_Filter>(
                    children: {
                      _Filter.official: Text('官网主修', style: segmentStyle),
                      _Filter.all: Text('全部', style: segmentStyle),
                      _Filter.included: Text('已计入', style: segmentStyle),
                    },
                    groupValue: _filter,
                    onValueChanged: (value) =>
                        setState(() => _filter = value ?? _Filter.official),
                  ),
                ],
              ),
            ),
          ),
          Obx(() {
            // 来源与覆盖表的改动都会 scholar.refresh()，这里只需观察 scholar
            var items = _buildItems();
            return SliverPadding(
              padding: const EdgeInsets.only(left: 18, right: 18, bottom: 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    var item = items[index];
                    if (item is String) {
                      return _buildSemesterHeader(context, item);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildGradeRow(context, item as Grade),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
