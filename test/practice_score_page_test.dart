import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:litechron/model/practice_details.dart';
import 'package:litechron/model/scholar.dart';
import 'package:litechron/page/scholar/practice_score/practice_score_controller.dart';
import 'package:litechron/page/scholar/practice_score/practice_score_page.dart';

import 'support/practice_fakes.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() async => Get.reset());

  Future<void> open(WidgetTester tester, PracticeTestScholar scholar,
      {int category = 1,
      double textScale = 1,
      Brightness brightness = Brightness.light}) async {
    Get.put<Rx<Scholar>>(Rx<Scholar>(scholar), tag: 'scholar');
    await tester.pumpWidget(GetCupertinoApp(
      theme: CupertinoThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: PracticeScorePage(initialCategory: category),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pull(WidgetTester tester) async {
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, 500));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('无缓存进入、切换课堂都不请求，下拉一次获取三类', (tester) async {
    final scholar = PracticeTestScholar();
    await open(tester, scholar);
    expect(scholar.requests, 0);
    expect(find.text('下拉加载实践明细'), findsOneWidget);
    expect(find.text('尚未更新'), findsOneWidget);
    expect(find.text('美育 —'), findsOneWidget);
    await tester.tap(find.text('第三课堂'));
    await tester.pumpAndSettle();
    expect(scholar.requests, 0);
    await pull(tester);
    expect(scholar.requests, 1);
    expect(find.text('示例实践项目'), findsOneWidget);
    await tester.tap(find.text('第二课堂'));
    await tester.pumpAndSettle();
    expect(scholar.requests, 1);
    expect(find.text('示例实践项目'), findsNWidgets(2));
    expect(find.text('美育 1.50'), findsOneWidget);
    expect(find.text('其他 2.00'), findsOneWidget);
    expect(find.text('6.50'), findsOneWidget);
    await close(tester);
  });

  testWidgets('缓存使用相对时间，美育筛选与进入详情不联网', (tester) async {
    final scholar = PracticeTestScholar(
        cached: practiceSnapshot(
            date: DateTime.now().subtract(const Duration(minutes: 5))));
    await open(tester, scholar);
    expect(scholar.requests, 0);
    expect(find.text('更新于 5 分钟前'), findsOneWidget);
    await tester.tap(find.text('美育 1.50'));
    await tester.pumpAndSettle();
    expect(find.text('示例实践项目'), findsOneWidget);
    await tester.tap(find.text('示例实践项目'));
    await tester.pumpAndSettle();
    expect(find.text('实践项目详情'), findsOneWidget);
    expect(find.text('参与身份或得分原因'), findsOneWidget);
    expect(find.text('示例说明'), findsOneWidget);
    expect(scholar.requests, 0);
    await close(tester);
  });

  testWidgets('无缓存手动刷新失败只弹一次具体原因，页内仍能重试', (tester) async {
    final scholar = PracticeTestScholar()
      ..response = () async => const PracticeDetails(error: '实践明细获取失败：请求超时');
    await open(tester, scholar);
    await pull(tester);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('刷新失败'), findsOneWidget);
    expect(find.text('实践明细获取失败：请求超时'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('下拉重试'), findsOneWidget);
    expect(find.text('尚未更新'), findsOneWidget);
    expect(scholar.requests, 1);
    scholar.response = null;
    await pull(tester);
    expect(scholar.requests, 2);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.textContaining('下拉重试'), findsNothing);
    await close(tester);
  });

  testWidgets('成功空列表不显示未加载提示，并且仍能下拉', (tester) async {
    final scholar =
        PracticeTestScholar(cached: PracticeDetails(updatedAt: DateTime.now()));
    await open(tester, scholar);
    expect(find.text('暂无第二课堂记录'), findsOneWidget);
    expect(find.text('美育 0.00'), findsOneWidget);
    expect(scholar.requests, 0);
    await pull(tester);
    expect(scholar.requests, 1);
    await close(tester);
  });

  testWidgets('大字体和深色模式无溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scholar = PracticeTestScholar(cached: practiceSnapshot());
    await open(tester, scholar, textScale: 2, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(scholar.requests, 0);
    await close(tester);
  });

  testWidgets('刷新期间离开页面不会弹出迟到错误', (tester) async {
    final gate = Completer<PracticeDetails>();
    final scholar = PracticeTestScholar()..response = () => gate.future;
    await open(tester, scholar);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(scholar.requests, 1);
    await close(tester);
    gate.complete(const PracticeDetails(error: '实践明细获取失败：请求超时'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('账号切换后忽略旧结果，后续下拉使用新账号', () async {
    final first = PracticeTestScholar(cached: practiceSnapshot());
    final gate = Completer<PracticeDetails>();
    first.response = () => gate.future;
    final global = Rx<Scholar>(first);
    final controller =
        Get.put(PracticeScoreController(initialCategory: 1, scholar: global));
    final oldRequest = controller.refreshDetails();
    final second = PracticeTestScholar();
    global.value = second;
    expect(controller.details.value.hasCache, isFalse);
    gate.complete(practiceSnapshot());
    expect(await oldRequest, isNull);
    expect(controller.details.value.hasCache, isFalse);
    await controller.refreshDetails();
    expect(first.requests, 1);
    expect(second.requests, 1);
    expect(controller.details.value.hasCache, isTrue);
  });

  test('重复下拉共享请求，失败保持原缓存时间', () async {
    final cached = practiceSnapshot(date: DateTime(2026, 9, 1));
    final scholar = PracticeTestScholar(cached: cached);
    final gate = Completer<PracticeDetails>();
    scholar.response = () => gate.future;
    final controller = Get.put(PracticeScoreController(
        initialCategory: 1, scholar: Rx<Scholar>(scholar)));
    final first = controller.refreshDetails();
    final second = controller.refreshDetails();
    expect(scholar.requests, 1);
    gate.complete(cached.withError('实践明细获取失败：请求超时'));
    expect(await first, '实践明细获取失败：请求超时');
    expect(await second, '实践明细获取失败：请求超时');
    expect(controller.details.value.updatedAt, cached.updatedAt);
    expect(controller.items, hasLength(2));
  });
}
