import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/model/task.dart';

/// Read-only expansion: never advances the user's persisted repeating tasks.
Map<String, dynamic> buildUpcomingSnapshot(
    Iterable<Period> academic, Iterable<Task> tasks, DateTime now) {
  final first = DateTime(now.year, now.month, now.day);
  final until = DateTime(now.year, now.month, now.day + 30);
  final entries = <String, Map<String, dynamic>>{};
  void add(String source, String type, String title, String location,
      DateTime start, DateTime end) {
    if (!end.isAfter(first) || !start.isBefore(until) || !end.isAfter(start)) {
      return;
    }
    final id =
        '$type:$source:${start.millisecondsSinceEpoch}:${end.millisecondsSinceEpoch}';
    entries[id] = {
      'id': id,
      'type': type,
      'title': title,
      'location': location,
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    };
  }

  for (final p in academic) {
    if (p.type != PeriodType.classes && p.type != PeriodType.test) continue;
    add(p.uid, p.type == PeriodType.test ? 'exam' : 'course', p.summary,
        p.location, p.startTime, p.endTime);
  }
  for (final task in tasks) {
    if (task.type == TaskType.deadline || task.status == TaskStatus.deleted) {
      continue;
    }
    final copy = task.copyWith();
    // Archived occurrences still establish whether today has already finished.
    if (copy.type == TaskType.fixedlegacy ||
        copy.repeatType == TaskRepeatType.norepeat) {
      add(task.fromUid ?? task.uid, 'schedule', copy.summary, copy.location,
          copy.startTime, copy.endTime);
      continue;
    }
    while (
        copy.status != TaskStatus.outdated && copy.startTime.isBefore(until)) {
      add(task.uid, 'schedule', copy.summary, copy.location, copy.startTime,
          copy.endTime);
      final previous = copy.startTime;
      copy.setToNextPeriod();
      if (!copy.startTime.isAfter(previous)) break;
    }
  }
  final items = entries.values.toList()
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  return {
    'version': 1,
    'generatedAt': now.millisecondsSinceEpoch,
    'from': first.millisecondsSinceEpoch,
    'until': until.millisecondsSinceEpoch,
    'timeZoneOffsetMinutes': now.timeZoneOffset.inMinutes,
    'items': items,
  };
}

class UpcomingWidgetSync {
  static const channel =
      MethodChannel('io.github.bno3bno3.litechron/upcomingWidget');
  static final openFlow = 0.obs;
  static Timer? _timer;
  static String? _account;
  static String? _signature;
  static int _generation = DateTime.now().microsecondsSinceEpoch;
  static Future<void> _pending = Future.value();

  static void start() {
    if (!Platform.isAndroid) return;
    ever(Get.find<Rx<Scholar>>(tag: 'scholar'), (_) => schedule());
    ever(Get.find<RxList<Task>>(tag: 'taskList'), (_) => schedule());
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
    _timer = Timer(const Duration(milliseconds: 250), () {
      final generation = _generation;
      final snapshot = buildUpcomingSnapshot(
          Get.find<Rx<Scholar>>(tag: 'scholar').value.periods,
          Get.find<RxList<Task>>(tag: 'taskList'),
          DateTime.now());
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
