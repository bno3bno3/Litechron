enum TodoFilter {
  all('总计', '全部作业', '暂无作业', null),
  oneDay('一天内', '当前学期 · 未来一天内', '未来一天内暂无作业截止', Duration(days: 1)),
  oneWeek('一周内', '当前学期 · 未来一周内', '未来一周内暂无作业截止', Duration(days: 7));

  const TodoFilter(this.label, this.scope, this.emptyMessage, this.window);

  final String label;
  final String scope;
  final String emptyMessage;
  final Duration? window;
}
