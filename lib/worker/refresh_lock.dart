import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/utils.dart';

/// 前台刷新与后台刷新之间的互斥标记。
///
/// 教务网同一账号只保留一个会话：前台 App 与后台任务各自跑在独立的 isolate
/// 里，各持一套 Zdbk 会话，任何一方登录都会把另一方正在进行的抓取顶下线，
/// 对方重登又会反过来顶掉这一方，几个来回就把自动重登次数耗尽。
/// 这里用 secure storage 里的时间戳当跨进程锁：一方开始刷新前先看对方是否
/// 正在刷新，后台直接跳过本轮，前台则等待对方结束再开始。
///
/// 所有操作都吞掉异常（例如测试环境没有平台插件），失败时视为“没有锁”。
class RefreshLock {
  RefreshLock._();

  static const foregroundKey = 'foregroundRefreshLock';
  static const backgroundKey = 'backgroundRefreshLock';

  /// 只有真正运行在设备上时才启用；测试环境没有平台通道，且期望刷新同步启动
  static bool enabled = false;

  /// 超过这个时间的锁视为持有者已经异常退出，不再等待
  static Duration staleAfter = const Duration(minutes: 3);

  static const _storage = FlutterSecureStorage();

  static Future<void> acquire(String key) async {
    try {
      await _storage.write(
          key: key,
          value: DateTime.now().millisecondsSinceEpoch.toString(),
          iOptions: secureStorageIOSOptions);
    } catch (_) {}
  }

  static Future<void> release(String key) async {
    try {
      await _storage.delete(key: key, iOptions: secureStorageIOSOptions);
    } catch (_) {}
  }

  /// 对方是否正在刷新（锁存在且未过期）
  static Future<bool> isHeld(String key) async {
    try {
      final raw =
          await _storage.read(key: key, iOptions: secureStorageIOSOptions);
      final since = int.tryParse(raw ?? '');
      if (since == null) return false;
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(since));
      return age >= Duration.zero && age < staleAfter;
    } catch (_) {
      return false;
    }
  }

  /// 等待 [key] 被释放或过期，最多等 [timeout]；返回是否已空闲
  static Future<bool> waitUntilFree(String key,
      {Duration timeout = const Duration(seconds: 45),
      Duration pollInterval = const Duration(seconds: 2)}) async {
    final deadline = DateTime.now().add(timeout);
    while (await isHeld(key)) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future.delayed(pollInterval);
    }
    return true;
  }
}
