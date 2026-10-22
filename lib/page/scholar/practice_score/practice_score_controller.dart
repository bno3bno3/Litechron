import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:litechron/model/practice_details.dart';
import 'package:litechron/model/practice_score_item.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/utils/refresh_time.dart';

class PracticeScoreController extends GetxController
    with WidgetsBindingObserver {
  final Rx<Scholar> _scholar;
  final RxInt category;
  final filter = PracticeFilter.all.obs;
  final details = const PracticeDetails().obs;
  final refreshing = false.obs;
  final DateTime Function() _now;
  late final now = _now().obs;
  Timer? _timer;
  bool _paused = false;
  Worker? _accountWorker;
  Scholar? _owner;
  String? _account;
  bool _loggedIn = false;
  int _generation = 0;
  Future<String?>? _refresh;

  PracticeScoreController(
      {required int initialCategory,
      Rx<Scholar>? scholar,
      DateTime Function()? now})
      : _scholar = scholar ?? Get.find<Rx<Scholar>>(tag: 'scholar'),
        _now = now ?? DateTime.now,
        category = initialCategory.obs;

  Scholar get scholar => _scholar.value;
  List<PracticeScoreItem> get items =>
      details.value.records(category.value, filter.value);
  String get categoryName => const ['第二课堂', '第三课堂', '第四课堂'][category.value - 1];
  double get total =>
      [scholar.pt2, scholar.pt3, scholar.pt4][category.value - 1];
  String get updateText {
    final date = details.value.updatedAt;
    if (date == null) return '尚未更新';
    final minutes = now.value.difference(date).inMinutes.clamp(0, 1000000000);
    return '更新于 $minutes 分钟前';
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _syncAccount();
    _accountWorker = ever(_scholar, (_) => _syncAccount());
  }

  void _updateClock() {
    _timer?.cancel();
    now.value = _now();
    final updatedAt = details.value.updatedAt;
    if (_paused || isClosed || updatedAt == null) return;
    final next = nextMinuteChange(updatedAt, now.value, clampNegative: true);
    _timer = Timer(next.difference(now.value), _updateClock);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      _updateClock();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _paused = true;
      _timer?.cancel();
    }
  }

  void _syncAccount() {
    if (identical(_owner, scholar) &&
        _account == scholar.username &&
        _loggedIn == scholar.isLogan) {
      return;
    }
    _generation++;
    _owner = scholar;
    _account = scholar.username;
    _loggedIn = scholar.isLogan;
    _refresh = null;
    refreshing.value = false;
    filter.value = PracticeFilter.all;
    // Reading local cache never authenticates or issues a network request.
    details.value = scholar.cachedPracticeDetails;
    _updateClock();
  }

  void selectCategory(int value) {
    category.value = value;
    filter.value = PracticeFilter.all;
  }

  Future<String?> refreshDetails() {
    _syncAccount();
    return _refresh ??= _doRefresh(_generation, scholar, scholar.username);
  }

  Future<String?> _doRefresh(
      int generation, Scholar owner, String? account) async {
    refreshing.value = true;
    final previous = details.value;
    details.value = PracticeDetails(
        items: previous.items,
        updatedAt: previous.updatedAt,
        complete: previous.complete);
    try {
      final result = await owner.getPracticeDetails();
      if (!_isCurrent(generation, owner, account)) return null;
      details.value = result;
      return result.error;
    } on Object {
      if (!_isCurrent(generation, owner, account)) return null;
      const error = '实践明细刷新失败：未知错误';
      details.value = previous.withError(error);
      return error;
    } finally {
      if (_isCurrent(generation, owner, account)) {
        _updateClock();
        refreshing.value = false;
        _refresh = null;
      }
    }
  }

  bool _isCurrent(int generation, Scholar owner, String? account) =>
      !isClosed &&
      generation == _generation &&
      identical(scholar, owner) &&
      scholar.username == account &&
      scholar.isLogan == _loggedIn;

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _paused = true;
    _generation++;
    _timer?.cancel();
    _accountWorker?.dispose();
    super.onClose();
  }
}
