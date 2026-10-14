// Adapted from Celechron/Celechron (GPL-3.0).
import 'package:litechron/utils/json_utils.dart';

/// 素拓响应的隐私最小化模型，仅保留展示和汇总所需字段。
class PracticeScoreItem {
  final int id;
  final int categoryId;
  final String categoryName;
  final String projectName;
  final String projectType;
  final String qualityType;
  final double score;
  final int? statusValue;
  final String statusLabel;
  final bool approved;
  final bool deleted;
  final String? role;
  final String? remark;
  final DateTime? activityStart;
  final DateTime? activityEnd;
  final DateTime? updatedAt;

  const PracticeScoreItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.projectName,
    required this.projectType,
    required this.qualityType,
    required this.score,
    required this.statusValue,
    required this.statusLabel,
    required this.approved,
    required this.deleted,
    required this.role,
    required this.remark,
    required this.activityStart,
    required this.activityEnd,
    required this.updatedAt,
  });

  /// 只有审核通过、未删除且分值有效的二/三/四课堂记录计入汇总。
  bool get countsTowardTotal =>
      approved &&
      !deleted &&
      categoryId >= 1 &&
      categoryId <= 3 &&
      score.isFinite &&
      score >= 0;

  bool get hasQualityType =>
      qualityType.trim().isNotEmpty && qualityType != '未填写';

  // Only the platform's quality classification is used, never the project name.
  bool get isAesthetic =>
      hasQualityType && RegExp(r'美育|艺术素养|审美情趣').hasMatch(qualityType);

  factory PracticeScoreItem.fromSztzJson(Map<String, dynamic> json) {
    final id = asInt(json['id']);
    if (id == null) {
      throw const FormatException('实践记录缺少有效 ID');
    }

    // jd 是当前学生实际获得记点；xm 下的分数字段属于项目范围，不参与计算。
    final project = asStringMap(json['xm']) ?? const <String, dynamic>{};
    final category = asStringMap(project['xmfl']) ?? const <String, dynamic>{};
    final projectType =
        asStringMap(project['xmlb']) ?? const <String, dynamic>{};
    final qualityType =
        asStringMap(project['xmlx']) ?? const <String, dynamic>{};
    final status = asStringMap(json['cyrshzt']) ?? const <String, dynamic>{};
    final currentState =
        asStringMap(json['currentState']) ?? const <String, dynamic>{};

    // 优先使用分类 ID；中文名称只为旧响应缺少 ID 时提供兼容映射。
    var categoryName = _text(category['mc']) ?? '未分类课堂';
    var categoryId = asInt(category['id']) ?? 0;
    if (categoryId == 0) {
      categoryId = switch (categoryName) {
        '第二课堂' => 1,
        '第三课堂' => 2,
        '第四课堂' => 3,
        _ => 0,
      };
    }
    if (categoryName == '未分类课堂') {
      categoryName = switch (categoryId) {
        1 => '第二课堂',
        2 => '第三课堂',
        3 => '第四课堂',
        _ => categoryName,
      };
    }

    final statusValue = asInt(status['value']);
    final statusLabel =
        _text(status['label']) ?? _text(currentState['name']) ?? '状态未知';
    final rawScore = asDouble(json['jd']);
    final score = rawScore != null && rawScore.isFinite ? rawScore : -1.0;

    return PracticeScoreItem(
      id: id,
      categoryId: categoryId,
      categoryName: categoryName,
      projectName: _text(project['mc']) ?? '未命名项目',
      projectType: _text(projectType['mc']) ?? '未填写',
      qualityType: _text(qualityType['mc']) ?? '未填写',
      score: score,
      statusValue: statusValue,
      statusLabel: statusLabel,
      approved: statusValue == 5 || statusLabel == '审核通过',
      deleted: asBool(json['sfsc']) ?? false,
      role: _text(json['hdjjygrcdgz']),
      remark: _text(json['qksm']),
      activityStart: _localDate(json['hdsj']),
      activityEnd: _localDate(json['hdjssj']),
      updatedAt: _localDate(json['gxsj']),
    );
  }

  factory PracticeScoreItem.fromJson(Map<String, dynamic> json) {
    final id = asInt(json['id']);
    if (id == null) {
      throw const FormatException('本地实践记录缺少有效 ID');
    }
    final statusLabel = _text(json['statusLabel']) ?? '状态未知';
    final statusValue = asInt(json['statusValue']);
    return PracticeScoreItem(
      id: id,
      categoryId: asInt(json['categoryId']) ?? 0,
      categoryName: _text(json['categoryName']) ?? '未分类课堂',
      projectName: _text(json['projectName']) ?? '未命名项目',
      projectType: _text(json['projectType']) ?? '未填写',
      qualityType: _text(json['qualityType']) ?? '未填写',
      score: asDouble(json['score']) ?? -1,
      statusValue: statusValue,
      statusLabel: statusLabel,
      approved: asBool(json['approved']) ??
          (statusValue == 5 || statusLabel == '审核通过'),
      deleted: asBool(json['deleted']) ?? false,
      role: _text(json['role']),
      remark: _text(json['remark']),
      activityStart: _localDate(json['activityStart']),
      activityEnd: _localDate(json['activityEnd']),
      updatedAt: _localDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'projectName': projectName,
        'projectType': projectType,
        'qualityType': qualityType,
        'score': score,
        'statusValue': statusValue,
        'statusLabel': statusLabel,
        'approved': approved,
        'deleted': deleted,
        'role': role,
        'remark': remark,
        'activityStart': activityStart?.toIso8601String(),
        'activityEnd': activityEnd?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static List<PracticeScoreItem> parseSztzItems(
    Iterable<dynamic> values, {
    void Function(int index, Object error, StackTrace stackTrace)? onError,
  }) {
    // 外层记录 ID 是去重依据；单条损坏不应使整批实践数据失效。
    final byId = <int, PracticeScoreItem>{};
    var index = 0;
    for (final value in values) {
      try {
        final map = asStringMap(value);
        if (map == null) {
          throw const FormatException('实践记录不是对象');
        }
        final item = PracticeScoreItem.fromSztzJson(map);
        if (!item.deleted) byId.putIfAbsent(item.id, () => item);
      } on Object catch (error, stackTrace) {
        onError?.call(index, error, stackTrace);
      }
      index++;
    }
    return byId.values.toList(growable: false);
  }

  static Map<int, double> approvedTotals(Iterable<PracticeScoreItem> items) {
    final totals = <int, double>{1: 0, 2: 0, 3: 0};
    for (final item in items) {
      if (item.countsTowardTotal) {
        totals[item.categoryId] = (totals[item.categoryId] ?? 0) + item.score;
      }
    }
    return totals;
  }

  static String? _text(Object? value) {
    final text = asString(value)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _localDate(Object? value) {
    final parsed = asDateTime(value);
    return parsed?.toLocal();
  }
}
