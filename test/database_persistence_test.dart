import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:litechron/database/database_helper.dart';
import 'package:litechron/model/scholar.dart';

import 'support/refresh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> secureValues;
  late List<MethodCall> calls;

  setUp(() {
    secureValues = {};
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'read':
          return secureValues[args['key']];
        case 'write':
          secureValues[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          secureValues.remove(args['key']);
          return null;
        case 'readAll':
          return Map<String, String>.from(secureValues);
        default:
          throw StateError('Unexpected storage operation: ${call.method}');
      }
    });
  });

  tearDown(() async {
    await Hive.close();
    Hive.resetAdapters();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<DatabaseHelper> openDatabase(Map<String, String> values) async {
    secureValues.addAll(values);
    final db = DatabaseHelper();
    // 使用 Hive 的内存后端，实际执行 init 和 adapter 写入，不创建用户数据文件。
    for (final name in [
      db.dbOptions,
      db.dbScholar,
      db.dbTask,
      db.dbFlow,
      db.dbOriginalWebPage,
      db.dbFuse,
      db.dbCustomGpa,
    ]) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
    await db.init();
    return db;
  }

  Map<String, String> account(String name,
          {String password = 'mock-password'}) =>
      {'username': name, 'password': password};

  test('已迁移的账号启动时只检查迁移标记，不删除或重写安全存储', () async {
    final values = {
      'accountList': jsonEncode([account('mock-a')]),
      'username': 'mock-a',
      'password': 'mock-password',
      'notifiedDdlIds_mock-a': '["example"]',
    };
    await openDatabase(values);
    expect(calls.map((call) => call.method), ['read']);
    expect(secureValues, values);
  });

  test('仍保留单账号到多账号的迁移，并且不重写旧凭据', () async {
    final db = await openDatabase({
      'username': 'mock-a',
      'password': 'mock-password',
      'gpa': '4.0',
      'gradedCourseCount': '2',
    });
    expect(await db.getAccountList(), [account('mock-a')]);
    expect(secureValues['gpa_mock-a'], '4.0');
    expect(secureValues['gradedCourseCount_mock-a'], '2');
    expect(calls.any((call) => call.method == 'readAll'), isFalse);
    expect(calls.any((call) => call.method == 'delete'), isFalse);
    final writtenKeys = calls
        .where((call) => call.method == 'write')
        .map((call) => (call.arguments as Map)['key']);
    expect(writtenKeys, isNot(contains('username')));
    expect(writtenKeys, isNot(contains('password')));
  });

  test('保存学业数据和重算 GPA 不访问安全存储，读取时仍恢复活动凭据', () async {
    final db = await openDatabase({
      'accountList': '[]',
      'username': 'mock-a',
      'password': 'mock-password',
    });
    final scholar = Scholar()
      ..db = db
      ..isLogan = true
      ..username = 'mock-a'
      ..password = 'mock-password'
      ..lastUpdateTimeGrade = DateTime(2026, 10, 23);
    calls.clear();
    await db.setScholar(scholar);
    await scholar.recalculateGpa();
    expect(calls, isEmpty);

    // 模拟重启后从 adapter 还原的不含凭据的学业对象。
    await db.scholarBox.put(
        'user',
        Scholar.fromJson(
            jsonDecode(jsonEncode(scholar)) as Map<String, dynamic>));
    final restored = await db.getScholar();
    expect(restored.isLogan, isTrue);
    expect(restored.username, 'mock-a');
    expect(restored.password, 'mock-password');
    expect(restored.lastUpdateTimeGrade, DateTime(2026, 10, 23));
  });

  test('账号列表提交同步当前凭据，每次只写一份镜像；改密码和切换立即生效', () async {
    final db = await openDatabase({'accountList': '[]'});
    calls.clear();
    await db.setAccountList([account('mock-a'), account('mock-b')]);
    expect(calls.map((call) => (call.arguments as Map)['key']),
        ['accountList', 'username', 'password']);
    expect(secureValues['username'], 'mock-a');

    await db.setAccountList([
      account('mock-a', password: 'mock-new-password'),
      account('mock-b'),
    ]);
    expect(secureValues['password'], 'mock-new-password');
    await db.setAccountList([
      account('mock-b'),
      account('mock-a', password: 'mock-new-password'),
    ]);
    expect(secureValues['username'], 'mock-b');
    expect(secureValues['password'], 'mock-password');
  });

  test('登录成功保存学业与凭据，失败不替换当前账号', () async {
    final db = await openDatabase({'accountList': '[]'});
    final spider = ControlledSpider();
    final scholar = Scholar(spiderFactory: (_, __) => spider)
      ..db = db
      ..username = 'mock-a'
      ..password = 'mock-password';
    expect(await scholar.login(), [null]);
    expect(secureValues['username'], 'mock-a');
    expect((db.scholarBox.get('user') as Scholar).isLogan, isTrue);

    scholar.password = 'mock-wrong-password';
    spider.loginGate = Completer<List<String?>>()
      ..complete(['mock login failure']);
    calls.clear();
    expect(await scholar.login(), ['mock login failure']);
    expect(calls, isEmpty);
    expect(secureValues['password'], 'mock-password');
  });

  test('账号切换使旧登录失去 db 后，不得覆盖活动凭据', () async {
    final db = await openDatabase({
      'accountList': '[]',
      'username': 'mock-active',
      'password': 'mock-active-password',
    });
    final gate = Completer<List<String?>>();
    final spider = ControlledSpider()..loginGate = gate;
    final old = Scholar(spiderFactory: (_, __) => spider)
      ..db = db
      ..username = 'mock-old'
      ..password = 'mock-old-password';
    final login = old.login();
    old.db = null;
    calls.clear();
    gate.complete([null]);
    await login;
    expect(calls, isEmpty);
    expect(secureValues['username'], 'mock-active');
    expect(secureValues['password'], 'mock-active-password');
  });

  test('退出最后一个账号会清除活动凭据，保留已迁移的空账号列表', () async {
    final db = await openDatabase({'accountList': '[]'});
    await db.setAccountList([account('mock-a')]);
    await db.setAccountList([]);
    await db.removeScholar();
    expect(secureValues['username'], isNull);
    expect(secureValues['password'], isNull);
    expect(secureValues['accountList'], '[]');
    expect((await db.getScholar()).isLogan, isFalse);
  });
}
