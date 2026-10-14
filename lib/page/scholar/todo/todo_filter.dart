enum TodoFilter {
  all('总计', '暂无作业', null),
  oneDay('一天内', '未来一天内暂无作业截止', Duration(days: 1)),
  oneWeek('一周内', '未来一周内暂无作业截止', Duration(days: 7));

  const TodoFilter(this.label, this.emptyMessage, this.window);

  final String label;
  final String emptyMessage;
  final Duration? window;
}
