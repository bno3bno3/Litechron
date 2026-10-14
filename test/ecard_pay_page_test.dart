import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litechron/page/option/android_ecard_pay_page.dart';
import 'package:litechron/worker/ecard_widget_messenger.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = ECardWidgetMessenger.platform;
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'one initial request, rebuild does not fetch, repeated tap disabled',
      (tester) async {
    var calls = 0;
    final reply = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      expect(call.method, 'getBarcode');
      calls++;
      return reply.future;
    });
    await tester.pumpWidget(const CupertinoApp(home: AndroidECardPayPage()));
    await tester.pump();
    expect(calls, 1);
    await tester.tap(find.text('刷新二维码'));
    await tester.pumpWidget(const CupertinoApp(home: AndroidECardPayPage()));
    expect(calls, 1);
    reply.complete('3200000000000000');
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('failed refresh clears old code and shows error', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (++calls == 1) return '3200000000000000';
      throw PlatformException(code: 'busy', message: '请稍后重试');
    });
    await tester.pumpWidget(const CupertinoApp(home: AndroidECardPayPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新二维码'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('请稍后重试'), findsOneWidget);
  });

  testWidgets('completion after page disposal does not update state',
      (tester) async {
    final reply = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => reply.future);
    await tester.pumpWidget(const CupertinoApp(home: AndroidECardPayPage()));
    await tester.pumpWidget(const SizedBox());
    reply.complete('3200000000000000');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('account change clears code and rejects a late reply',
      (tester) async {
    final reply = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => reply.future);
    await tester.pumpWidget(const CupertinoApp(home: AndroidECardPayPage()));
    ECardWidgetMessenger.accountGeneration.value++;
    reply.complete('3200000000000000');
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('账号已切换，请重新打开付款码'), findsOneWidget);
  });
}
