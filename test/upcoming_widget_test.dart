import 'package:flutter_test/flutter_test.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/worker/upcoming_widget.dart';

void main() {
  final now = DateTime(2026, 10, 17, 12);
  test('snapshot contains all courses and excludes flow blocks', () {
    final periods = List.generate(
        9,
        (i) => Period(
            uid: '$i',
            startTime: DateTime(2026, 10, 17, i + 8),
            endTime: DateTime(2026, 10, 17, i + 9)));
    periods.add(periods.first.copyWith(uid: 'flow', type: PeriodType.flow));
    final result = buildUpcomingSnapshot(periods, [], now);
    expect(result['items'], hasLength(9));
  });
  test('repeating tasks retain full overnight intervals without mutation', () {
    final task = Task(
        uid: 'overnight',
        type: TaskType.fixed,
        startTime: DateTime(2026, 10, 16, 23),
        endTime: DateTime(2026, 10, 17, 2),
        repeatType: TaskRepeatType.days,
        repeatEndsTime: DateTime(2026, 10, 18));
    final result = buildUpcomingSnapshot([], [task], now);
    final items = result['items'] as List;
    expect(items, hasLength(3));
    expect(items.first['start'], task.startTime.millisecondsSinceEpoch);
    expect(task.startTime, DateTime(2026, 10, 16, 23));
    expect(items.map((e) => e['id']).toSet(), hasLength(3));
  });
  test(
      'archived occurrence deduplicates against active task and deleted is excluded',
      () {
    final task = Task(
        uid: 'one',
        type: TaskType.fixed,
        startTime: DateTime(2026, 10, 17, 8),
        endTime: DateTime(2026, 10, 17, 9),
        repeatEndsTime: now);
    final archived = task.copyWith()
      ..uid = 'archive'
      ..fromUid = 'one'
      ..type = TaskType.fixedlegacy;
    final deleted = task.copyWith()
      ..uid = 'deleted'
      ..status = TaskStatus.deleted;
    expect(buildUpcomingSnapshot([], [task, archived, deleted], now)['items'],
        hasLength(1));
  });
  test('specified dates and horizon respect existing recurrence rules', () {
    final task = Task(
        uid: 'dates',
        type: TaskType.fixed,
        startTime: DateTime(2026, 10, 17, 8),
        endTime: DateTime(2026, 10, 17, 9),
        repeatType: TaskRepeatType.dates,
        repeatEndsTime: DateTime(2026, 12, 1),
        repeatDates: [
          DateTime(2026, 10, 17),
          DateTime(2026, 10, 20),
          DateTime(2026, 12, 1)
        ]);
    expect(buildUpcomingSnapshot([], [task], now)['items'], hasLength(2));
  });
}
