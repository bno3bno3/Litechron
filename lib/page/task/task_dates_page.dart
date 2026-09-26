import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:litechron/utils/utils.dart';

/// Edits a private selection; only Done returns it to the task editor.
class TaskDatesPage extends StatefulWidget {
  final List<DateTime> dates;
  final DateTime firstEditableDay;
  final DateTime focusedDay;

  const TaskDatesPage({
    super.key,
    required this.dates,
    required this.firstEditableDay,
    required this.focusedDay,
  });

  @override
  State<TaskDatesPage> createState() => _TaskDatesPageState();
}

class _TaskDatesPageState extends State<TaskDatesPage> {
  late final Set<DateTime> _dates = widget.dates.map(dateOnly).toSet();
  late DateTime _focusedDay = widget.focusedDay;

  @override
  Widget build(BuildContext context) {
    final weekdayStyle = DefaultTextStyle.of(context).style.copyWith(
          fontSize: 14,
          height: 1.4,
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel, context),
        );
    // The calendar's default 16px header clips Chinese text. Measure with the
    // same font and system text scaling, then leave space above and below it.
    final weekdayPainter = TextPainter(
      text: TextSpan(text: '周一', style: weekdayStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: const Locale('zh', 'CN'),
      maxLines: 1,
    )..layout();
    final weekdayHeight =
        math.max(28.0, weekdayPainter.height.ceilToDouble() + 8);
    weekdayPainter.dispose();
    final sorted = _dates.toList()..sort();
    final months = <String, List<String>>{};
    for (final day in sorted) {
      months
          .putIfAbsent('${day.year}年${day.month}月', () => [])
          .add('${day.day}日');
    }
    final canSave = sorted.any((day) => !day.isBefore(widget.firstEditableDay));
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        middle: const Text('选择日期'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: canSave ? () => Navigator.of(context).pop(sorted) : null,
          child: const Text('完成'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: _focusedDay.year == 1900 && _focusedDay.month == 1
                      ? null
                      : () => setState(() {
                            _focusedDay = DateTime(
                                _focusedDay.year, _focusedDay.month - 1);
                          }),
                  child: const Icon(CupertinoIcons.chevron_left),
                ),
                Text('${_focusedDay.year}年${_focusedDay.month}月'),
                CupertinoButton(
                  onPressed: _focusedDay.year == 2099 && _focusedDay.month == 12
                      ? null
                      : () => setState(() {
                            _focusedDay = DateTime(
                                _focusedDay.year, _focusedDay.month + 1);
                          }),
                  child: const Icon(CupertinoIcons.chevron_right),
                ),
              ],
            ),
            TableCalendar<void>(
              locale: 'zh_CN',
              firstDay: DateTime(1900),
              lastDay: DateTime(2099, 12, 31),
              focusedDay: _focusedDay,
              startingDayOfWeek: StartingDayOfWeek.monday,
              availableGestures: AvailableGestures.horizontalSwipe,
              headerVisible: false,
              daysOfWeekHeight: weekdayHeight,
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: weekdayStyle,
                weekendStyle: weekdayStyle,
              ),
              enabledDayPredicate: (day) =>
                  !dateOnly(day).isBefore(widget.firstEditableDay),
              calendarBuilders: CalendarBuilders<void>(
                disabledBuilder: (context, day, focusedDay) => Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: _dates.contains(dateOnly(day))
                        ? BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemGrey4, context),
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text('${day.day}',
                        style: TextStyle(
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        )),
                  ),
                ),
              ),
              selectedDayPredicate: (day) => _dates.contains(dateOnly(day)),
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: CupertinoTheme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  border: Border.all(
                      color: CupertinoTheme.of(context).primaryColor),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
                defaultTextStyle: TextStyle(
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
              ),
              onPageChanged: (day) => setState(() => _focusedDay = day),
              onDaySelected: (day, focused) {
                day = dateOnly(day);
                if (day.isBefore(widget.firstEditableDay)) return;
                setState(() {
                  _focusedDay = focused;
                  if (!_dates.remove(day)) _dates.add(day);
                });
              },
            ),
            CupertinoListSection.insetGrouped(
              header: Text('已选 ${sorted.length} 天'),
              footer: const Text('点击日期选中或取消，已结束的日程日期仅供查看。'),
              children: [
                for (final entry in months.entries)
                  CupertinoListTile(
                    title: Text(entry.key),
                    subtitle: Text(entry.value.join('、'), maxLines: null),
                  ),
                if (months.isEmpty)
                  const CupertinoListTile(title: Text('请至少选择一个日期')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
