import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/scholar.dart';

/// Mirrors the page's prepared list without expanding or reordering it.
Map<String, dynamic> buildUpcomingSnapshot(
    Iterable<Period> periods, DateTime now) {
  final items = <Map<String, dynamic>>[];
  for (final period in periods) {
    final type = switch (period.type) {
      PeriodType.classes => 'course',
      PeriodType.test => 'exam',
      PeriodType.user => 'schedule',
      PeriodType.flow => 'flow',
      PeriodType.virtual => null,
    };
    if (type == null || !period.endTime.isAfter(period.startTime)) continue;
    // Repeating schedules share a source UID; their interval identifies each
    // occurrence. Description/progress changes must not change card identity.
    final source = period.type == PeriodType.user
        ? period.fromUid ?? period.uid
        : period.uid;
    final start = period.startTime.millisecondsSinceEpoch;
    final end = period.endTime.millisecondsSinceEpoch;
    items.add({
      'id': '$type:$source:$start:$end',
      'type': type,
      'title': period.summary,
      'location': period.location,
      'start': start,
      'end': end,
    });
  }
  return {
    'version': 2,
    'generatedAt': now.millisecondsSinceEpoch,
    'items': items,
  };
}

class UpcomingWidgetSync {
  static const channel =
      MethodChannel('io.github.bno3bno3.litechron/upcomingWidget');
  static final openFlow = 0.obs;
  static Timer? _timer;
  static Worker? _scholarWorker;
  static Worker? _flowWorker;
  static bool _flowListReady = false;
  static String? _account;
  static String? _signature;
  static int _generation = DateTime.now().microsecondsSinceEpoch;
  static Future<void> _pending = Future.value();

  static void start() {
    if (!Platform.isAndroid || _scholarWorker != null) return;
    _scholarWorker = ever(Get.find<Rx<Scholar>>(tag: 'scholar'), (_) {
      // Wait for the page to merge refreshed academic data before publishing.
      _flowListReady = false;
      schedule();
    });
    _flowWorker =
        ever(Get.find<RxList<Period>>(tag: 'flowList'), (_) => schedule());
    schedule();
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _scholarWorker?.dispose();
    _scholarWorker = null;
    _flowWorker?.dispose();
    _flowWorker = null;
    _flowListReady = false;
    _account = null;
    _signature = null;
    // 已排队的旧页面快照不能在其销毁后继续发布。
    _generation++;
  }

  /// Called after the page has finished preparing its shared list.
  static void flowListPrepared() {
    if (!Platform.isAndroid) return;
    _flowListReady = true;
    schedule();
  }

  static void schedule() {
    if (!Platform.isAndroid) return;
    final account = Get.find<Rx<Scholar>>(tag: 'scholar').value.username ?? '';
    if (_account != account) {
      // Reuse colors on startup; reset them when the user switches accounts.
      final preserveColors = _account == null;
      _account = account;
      _generation++;
      _signature = null;
      final generation = _generation;
      _pending = _pending.then((_) async {
        await channel.invokeMethod('invalidateSnapshot', {
          'generation': generation,
          'preserveColors': preserveColors,
        });
      }).catchError((_) {});
    }
    _timer?.cancel();
    if (!_flowListReady) return;
    _timer = Timer(const Duration(milliseconds: 250), () {
      final generation = _generation;
      final snapshot = buildUpcomingSnapshot(
          Get.find<RxList<Period>>(tag: 'flowList'), DateTime.now());
      final signature = jsonEncode({...snapshot}..remove('generatedAt'));
      if (_signature == signature) return;
      snapshot['generation'] = generation;
      _pending = _pending.then((_) async {
        if (generation != _generation) return;
        await channel.invokeMethod('publishSnapshot', jsonEncode(snapshot));
        if (generation == _generation) _signature = signature;
      }).catchError((_) {});
    });
  }
}
