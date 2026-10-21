import 'package:flutter_test/flutter_test.dart';
import 'package:litechron/model/period.dart';
import 'package:litechron/worker/upcoming_widget.dart';

void main() {
  final now = DateTime(2026, 10, 21, 12);
  Period period(String uid, PeriodType type, {int day = 21}) => Period(
        uid: uid,
        type: type,
        summary: uid,
        location: '示例地点',
        startTime: DateTime(2026, 10, day, 13),
        endTime: DateTime(2026, 10, day, 14),
      );

  test('snapshot mirrors all four page item types in the page order', () {
    final periods = [
      period('schedule', PeriodType.user),
      period('course', PeriodType.classes),
      period('flow', PeriodType.flow),
      period('exam', PeriodType.test),
    ];
    final result = buildUpcomingSnapshot(periods, now);
    final items = result['items'] as List;
    expect(result['version'], 2);
    expect(items.map((e) => e['title']), periods.map((e) => e.summary));
    expect(items.map((e) => e['type']), ['schedule', 'course', 'flow', 'exam']);
    expect(items.every((e) => e['location'] == '示例地点'), isTrue);
    expect(periods.map((e) => e.uid), ['schedule', 'course', 'flow', 'exam']);
  });

  test('snapshot has no date horizon or independent recurrence expansion', () {
    final periods = [
      period('tomorrow', PeriodType.classes, day: 22),
      period('later', PeriodType.user, day: 40),
      period('far-flow', PeriodType.flow, day: 80),
    ];
    final result = buildUpcomingSnapshot(periods, now);
    final items = result['items'] as List;
    expect(items.map((e) => e['title']), ['tomorrow', 'later', 'far-flow']);
    expect(items.last['end'], periods.last.endTime.millisecondsSinceEpoch);
    expect(result.containsKey('until'), isFalse);
  });

  test('overnight intervals and repeated occurrence identities stay intact',
      () {
    final overnight = period('default', PeriodType.user)
      ..fromUid = 'repeating-task'
      ..startTime = DateTime(2026, 10, 20, 23)
      ..endTime = DateTime(2026, 10, 21, 14);
    final next = overnight.copyWith(
      startTime: DateTime(2026, 10, 21, 23),
      endTime: DateTime(2026, 10, 22, 14),
    );
    final items =
        buildUpcomingSnapshot([overnight, next], now)['items'] as List;
    expect(items, hasLength(2));
    expect(items.map((e) => e['id']).toSet(), hasLength(2));
    expect(items.first['start'], overnight.startTime.millisecondsSinceEpoch);
    expect(overnight.startTime, DateTime(2026, 10, 20, 23));
  });

  test('progress-only changes do not change published content or identity', () {
    final flow = period('flow', PeriodType.flow);
    final before = buildUpcomingSnapshot([flow], now)..remove('generatedAt');
    flow.lastUpdateTime = now.add(const Duration(seconds: 1));
    final after = buildUpcomingSnapshot([flow], flow.lastUpdateTime!)
      ..remove('generatedAt');
    expect(after, before);
    flow.summary = '更新后的任务名称';
    final updated = buildUpcomingSnapshot([flow], now)['items'] as List;
    expect(updated.single['id'], (before['items'] as List).single['id']);
    expect(updated.single['title'], '更新后的任务名称');
    expect(buildUpcomingSnapshot([], now)['items'], isEmpty);
  });

  test('internal placeholders and invalid intervals are not widget cards', () {
    final invalid = period('invalid', PeriodType.classes);
    invalid.endTime = invalid.startTime;
    expect(
      buildUpcomingSnapshot([
        period('virtual', PeriodType.virtual),
        invalid,
      ], now)['items'],
      isEmpty,
    );
  });
}
