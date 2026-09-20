import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import 'package:litechron/design/persistent_headers.dart';
import 'package:litechron/model/option.dart';
import 'package:litechron/model/recommend_gpa_rule.dart';
import 'package:litechron/page/scholar/grade_detail/weighted_gpa_view.dart';
import 'option_controller.dart';

/// 推免绩点规则页
///
/// 推免绩点 = 主修均绩占比 × 主修均绩 + 总均绩占比 × 加权总均绩，
/// 加权总均绩中主修课绩点乘以主修课权重（单门覆盖优先）。
class RecommendGpaRulePage extends StatefulWidget {
  const RecommendGpaRulePage({super.key});

  @override
  State<RecommendGpaRulePage> createState() => _RecommendGpaRulePageState();
}

class _RecommendGpaRulePageState extends State<RecommendGpaRulePage> {
  final _optionController = Get.find<OptionController>(tag: 'optionController');
  final _option = Get.find<Option>(tag: 'option');

  late final TextEditingController _weightController;
  late final TextEditingController _majorRatioController;
  late final TextEditingController _overallRatioController;
  final _weightFocus = FocusNode();
  final _majorRatioFocus = FocusNode();
  final _overallRatioFocus = FocusNode();

  RecommendGpaRule get _rule => _optionController.recommendGpaRule.value;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(text: _fmt(_rule.majorWeight));
    _majorRatioController = TextEditingController(text: _fmt(_rule.majorRatio));
    _overallRatioController =
        TextEditingController(text: _fmt(_rule.overallRatio));
    // 失焦时提交：静默裁剪到范围内，占比两项联动保持相加为 1
    _weightFocus.addListener(() {
      if (!_weightFocus.hasFocus) _commitWeight();
    });
    _majorRatioFocus.addListener(() {
      if (!_majorRatioFocus.hasFocus) _commitMajorRatio();
    });
    _overallRatioFocus.addListener(() {
      if (!_overallRatioFocus.hasFocus) _commitOverallRatio();
    });
  }

  @override
  void dispose() {
    _weightController.dispose();
    _majorRatioController.dispose();
    _overallRatioController.dispose();
    _weightFocus.dispose();
    _majorRatioFocus.dispose();
    _overallRatioFocus.dispose();
    super.dispose();
  }

  static String _fmt(double v) {
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  double? _parse(String text) => double.tryParse(text.trim());

  void _commitWeight() {
    if (!mounted) return;
    var v = _parse(_weightController.text) ?? _rule.majorWeight;
    var rule = _rule.copyWith(majorWeight: v);
    _weightController.text = _fmt(rule.majorWeight);
    _optionController.setRecommendGpaRule(rule);
  }

  void _commitMajorRatio() {
    if (!mounted) return;
    var v = RecommendGpaRule.clampRatio(
        _parse(_majorRatioController.text) ?? _rule.majorRatio);
    var rule = _rule.copyWith(majorRatio: v, overallRatio: 1 - v);
    _majorRatioController.text = _fmt(rule.majorRatio);
    _overallRatioController.text = _fmt(rule.overallRatio);
    _optionController.setRecommendGpaRule(rule);
  }

  void _commitOverallRatio() {
    if (!mounted) return;
    var v = RecommendGpaRule.clampRatio(
        _parse(_overallRatioController.text) ?? _rule.overallRatio);
    var rule = _rule.copyWith(overallRatio: v, majorRatio: 1 - v);
    _majorRatioController.text = _fmt(rule.majorRatio);
    _overallRatioController.text = _fmt(rule.overallRatio);
    _optionController.setRecommendGpaRule(rule);
  }

  Widget _numberField(TextEditingController controller, FocusNode focusNode,
      VoidCallback onDone) {
    return SizedBox(
      width: 80,
      child: CupertinoTextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onEditingComplete: () {
          onDone();
          focusNode.unfocus();
        },
        onTapOutside: (_) => focusNode.unfocus(),
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

  @override
  Widget build(BuildContext context) {
    var secondaryStyle = TextStyle(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondaryLabel, context),
        fontSize: 16);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          const LitechronSliverTextHeader(subtitle: '推免绩点规则'),
          SliverToBoxAdapter(
            child: CupertinoListSection.insetGrouped(
              margin: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 10),
              additionalDividerMargin: 2,
              children: [
                CupertinoListTile(
                  title: const Text('主修课权重'),
                  trailing: _numberField(
                      _weightController, _weightFocus, _commitWeight),
                ),
                CupertinoListTile(
                  title: const Text('主修均绩占比'),
                  trailing: _numberField(_majorRatioController,
                      _majorRatioFocus, _commitMajorRatio),
                ),
                CupertinoListTile(
                  title: const Text('总均绩占比'),
                  trailing: _numberField(_overallRatioController,
                      _overallRatioFocus, _commitOverallRatio),
                ),
                CupertinoListTile(
                  title: const Text('单门课程权重覆盖'),
                  trailing: Icon(CupertinoIcons.right_chevron,
                      size: 16,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.tertiaryLabel, context)),
                  onTap: () {
                    Navigator.of(context).push(CupertinoPageRoute(
                        builder: (context) => WeightedGpaPage()));
                  },
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: CupertinoListSection.insetGrouped(
              margin: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
              additionalDividerMargin: 2,
              children: [
                CupertinoListTile(
                  title: const Text('推免绩点'),
                  trailing: Obx(() {
                    var first = _option.gpaStrategy.value == GpaStrategy.first;
                    var value = _optionController
                        .scholar.value.recommendGpa[first ? 0 : 1];
                    return Text(value.toStringAsFixed(2),
                        style: secondaryStyle);
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
