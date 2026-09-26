// Hive's binary codecs let compatibility tests run without temporary files.
// ignore_for_file: implementation_imports

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/binary/binary_writer_impl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:litechron/database/adapters/deadline_adapter.dart';
import 'package:litechron/database/adapters/duration_adapter.dart';
import 'package:litechron/model/task.dart';
import 'package:litechron/page/task/task_dates_page.dart';

Task schedule() => Task(
      type: TaskType.fixed,
      startTime: DateTime(2026, 10, 8, 23),
      endTime: DateTime(2026, 10, 9, 1),
      repeatType: TaskRepeatType.dates,
      repeatDates: [DateTime(2026, 10, 8), DateTime(2026, 11, 2)],
      repeatEndsTime: DateTime(2026, 11, 2),
      blockArrangements: false,
    );

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  test('Hive restores selected dates and accepts the previous 16-field format',
      () {
    final hive = Hive;
    hive.registerAdapter(DurationAdapter());
    hive.registerAdapter(DeadlineStatusAdapter());
    hive.registerAdapter(DeadlineTypeAdapter());
    hive.registerAdapter(DeadlineRepeatTypeAdapter());
    final adapter = DeadlineAdapter();
    final writer = BinaryWriterImpl(hive);
    adapter.write(writer, schedule());
    final restored = adapter.read(BinaryReaderImpl(writer.toBytes(), hive));
    expect(restored.repeatDates, schedule().repeatDates);
    expect(restored.repeatType, TaskRepeatType.dates);
    expect(restored.blockArrangements, isFalse);

    final oldWriter = BinaryWriterImpl(hive);
    adapter.write(oldWriter, schedule()..repeatType = TaskRepeatType.days);
    final oldBytes = oldWriter.toBytes()..[0] = 16;
    final oldTask = adapter.read(BinaryReaderImpl(oldBytes, hive));
    expect(oldTask.repeatType, TaskRepeatType.days);
    expect(oldTask.repeatDates, isEmpty);
    expect(oldTask.startTime, schedule().startTime);
  });
  test('selected dates skip gaps and split overnight occurrences', () {
    final task = schedule();
    expect(task.getPeriodOfDay(DateTime(2026, 10, 10)), isEmpty);
    final overnight = task.getPeriodOfDay(DateTime(2026, 10, 9)).single;
    expect(overnight.startTime, DateTime(2026, 10, 9));
    expect(overnight.endTime, DateTime(2026, 10, 9, 1));
    expect(task.getPeriodOfDay(DateTime(2026, 11, 2)), hasLength(1));
    expect(
        task
            .deadlineOfTime(DateTime(2026, 10, 12), predicting: true)!
            .startTime,
        DateTime(2026, 11, 2, 23));
  });

  test('final occurrence remains expired after status refresh', () {
    final task = schedule();
    expect(task.setToNextPeriod(), isTrue);
    expect(task.startTime, DateTime(2026, 11, 2, 23));
    expect(task.endTime, DateTime(2026, 11, 3, 1));
    expect(task.setToNextPeriod(), isTrue);
    expect(task.status, TaskStatus.outdated);
    task.refreshStatus();
    expect(task.status, TaskStatus.outdated);
    expect(task.setToNextPeriod(), isFalse);
    expect(task.deadlineOfTime(DateTime(2026, 11, 3, 2), predicting: true),
        isNull);
    expect(task.getPeriodOfDay(DateTime(2026, 11, 4)), isEmpty);
  });

  test('editing a copy cannot mutate saved dates and triggers flow refresh',
      () {
    final original = schedule();
    final draft = original.copyWith();
    draft.repeatDates.add(DateTime(2026, 10, 15));
    expect(original.repeatDates, hasLength(2));
    expect(draft.differentForFlow(original), isTrue);
    original.copy(draft);
    draft.repeatDates.clear();
    expect(original.repeatDates, hasLength(3));
  });

  test('existing daily recurrence is unchanged', () {
    final task = schedule()..repeatType = TaskRepeatType.days;
    task.repeatPeriod = 3;
    task.setToNextPeriod();
    expect(task.startTime, DateTime(2026, 10, 11, 23));
    expect(task.endTime, DateTime(2026, 10, 12, 1));
  });

  testWidgets('date picker edits its own selection and toggles dates',
      (tester) async {
    final dates = [DateTime(2026, 10, 8)];
    await tester.pumpWidget(CupertinoApp(
      home: TaskDatesPage(
        dates: dates,
        firstEditableDay: DateTime(2026, 10, 1),
        focusedDay: DateTime(2026, 10, 8),
      ),
    ));
    await tester.tap(find.text('15').first);
    await tester.pump();
    expect(find.text('已选 2 天'), findsOneWidget);
    expect(dates, hasLength(1));
    await tester.tap(find.text('15').first);
    await tester.pump();
    expect(find.text('已选 1 天'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').first);
    await tester.pump();
    expect(find.text('已选 2 天'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 天'), findsOneWidget);
    expect(dates, hasLength(1));
  });
}
