/// Duration.inMinutes 的下一次显示变化；负时差按向零取整处理。
DateTime nextMinuteChange(DateTime updatedAt, DateTime now,
    {bool clampNegative = false}) {
  final minutes = now.difference(updatedAt).inMinutes;
  if (minutes < 0 && !clampNegative) {
    return updatedAt.add(Duration(minutes: minutes, microseconds: 1));
  }
  return updatedAt.add(Duration(minutes: minutes < 0 ? 1 : minutes + 1));
}
