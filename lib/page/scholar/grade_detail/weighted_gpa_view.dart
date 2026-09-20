import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:litechron/design/custom_colors.dart';
import 'package:litechron/design/round_rectangle_card.dart';
import 'package:litechron/design/two_line_card.dart';
import 'package:litechron/design/persistent_headers.dart';
import 'package:litechron/page/scholar/grade_detail/weighted_gpa_controller.dart';

/// 单门课程权重页
///
/// 推免绩点规则的补充：为个别课程单独指定权重（0 到 2），优先于规则里的主修课权重。
/// 输入框留空表示不覆盖，占位符显示当前按规则生效的权重。
/// 只列出计入 GPA 的课程，可按学期或全部查看；「重置」清空所有覆盖。
class WeightedGpaPage extends StatelessWidget {
  final _controller = Get.put(WeightedGpaController());

  WeightedGpaPage({super.key});

  Widget _buildSemesterPicker(BuildContext context) {
    return RoundRectangleCard(
      animate: false,
      child: Column(
        children: [
          SizedBox(
            height: 81,
            child: Obx(
              () => ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _controller.semestersWithGrades.length,
                itemBuilder: (context, index) {
                  final semester = _controller.semestersWithGrades[index];

                  return Obx(
                    () => Row(
                      children: [
                        TwoLineCard(
                          animate: true,
                          withColoredFont: true,
                          width: 120,
                          title:
                              '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                          content:
                              '${semester.gpa[0].toStringAsFixed(2)}/${semester.credits.toStringAsFixed(1)}',
                          onTap: () {
                            _controller.semesterIndex.value = index;
                            _controller.semesterIndex.refresh();
                          },
                          backgroundColor:
                              _controller.semesterIndex.value == index
                                  ? CustomCupertinoDynamicColors.cyan
                                  : CupertinoColors.systemFill,
                        ),
                        if (index != _controller.semestersWithGrades.length - 1)
                          const SizedBox(width: 6),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final semesterGrades = _controller.getCurrentSemesterGrades();
      // 只显示计入GPA的课程
      final affectGpaGrades =
          semesterGrades.where((g) => g.gpaIncluded).toList();
      // 按课程名排序
      affectGpaGrades.sort((a, b) => a.name.compareTo(b.name));

      return CupertinoPageScaffold(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        child: CustomScrollView(
          slivers: [
            LitechronSliverTextHeader(
              subtitle: '单门课程权重',
              right: Obx(
                () => Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Text(
                          '重置',
                          style: TextStyle(fontSize: 16),
                        ),
                        onPressed: () {
                          _controller.weightedMap.value = {};
                          _controller.refreshWeightedGpa();
                        },
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Text(
                          _controller.showAllSemesters.value ? '按学期' : '全部',
                          style: const TextStyle(fontSize: 16),
                        ),
                        onPressed: () {
                          _controller.showAllSemesters.value =
                              !_controller.showAllSemesters.value;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Obx(
                () => _controller.showAllSemesters.value
                    ? const SizedBox(height: 8)
                    : Column(
                        children: [
                          Row(
                            children: [
                              const SizedBox(width: 18),
                              Expanded(
                                child: _buildSemesterPicker(context),
                              ),
                              const SizedBox(width: 18),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final grade = affectGpaGrades[index];
                  return Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 18),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.only(
                                  left: 12, right: 8, bottom: 8, top: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.systemBackground, context),
                                boxShadow: [
                                  BoxShadow(
                                    color: CupertinoColors.black
                                        .withValues(alpha: 0.1),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          grade.name,
                                          style: CupertinoTheme.of(context)
                                              .textTheme
                                              .textStyle
                                              .copyWith(
                                                fontSize: 16,
                                                fontWeight: FontWeight.normal,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                        ),
                                        Text(
                                          '${grade.realId} / ${grade.credit.toStringAsFixed(1)} 学分',
                                          style: CupertinoTheme.of(context)
                                              .textTheme
                                              .textStyle
                                              .copyWith(
                                                color:
                                                    CupertinoTheme.of(context)
                                                        .textTheme
                                                        .textStyle
                                                        .color!
                                                        .withValues(alpha: 0.5),
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
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .copyWith(
                                          fontSize: 18,
                                          fontWeight: FontWeight.normal,
                                        ),
                                  ),
                                  const SizedBox(width: 12),
                                  Obx(() => _WeightField(
                                        key: ValueKey(grade.id),
                                        overrideWeight:
                                            _controller.getOverride(grade.id),
                                        placeholder:
                                            _controller.getDefaultWeight(grade),
                                        onCommit: (value) => _controller
                                            .setWeight(grade.id, value),
                                      )),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
                childCount: affectGpaGrades.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      );
    });
  }
}

/// 单门权重输入框：留空为不覆盖，失焦或回车时提交
class _WeightField extends StatefulWidget {
  final double? overrideWeight;
  final double placeholder;
  final void Function(double?) onCommit;

  const _WeightField({
    super.key,
    required this.overrideWeight,
    required this.placeholder,
    required this.onCommit,
  });

  @override
  State<_WeightField> createState() => _WeightFieldState();
}

class _WeightFieldState extends State<_WeightField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  static String _fmt(double v) {
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text:
            widget.overrideWeight == null ? '' : _fmt(widget.overrideWeight!));
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _WeightField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改动（如重置）时同步文本；编辑中不打断
    if (widget.overrideWeight != oldWidget.overrideWeight &&
        !_focusNode.hasFocus) {
      _controller.text =
          widget.overrideWeight == null ? '' : _fmt(widget.overrideWeight!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    if (!mounted) return;
    var text = _controller.text.trim();
    if (text.isEmpty) {
      if (widget.overrideWeight != null) widget.onCommit(null);
      return;
    }
    var value = double.tryParse(text);
    if (value == null) {
      _controller.text =
          widget.overrideWeight == null ? '' : _fmt(widget.overrideWeight!);
      return;
    }
    value = value.clamp(0.0, WeightedGpaController.maxWeight);
    _controller.text = _fmt(value);
    if (value != widget.overrideWeight) widget.onCommit(value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: CupertinoTextField(
        controller: _controller,
        focusNode: _focusNode,
        textAlign: TextAlign.right,
        placeholder: _fmt(widget.placeholder),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onEditingComplete: () {
          _commit();
          _focusNode.unfocus();
        },
        onTapOutside: (_) => _focusNode.unfocus(),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.tertiarySystemFill, context),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        style: CupertinoTheme.of(context)
            .textTheme
            .textStyle
            .copyWith(fontSize: 16),
      ),
    );
  }
}
