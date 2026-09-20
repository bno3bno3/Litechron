import 'dart:async';

import 'package:litechron/model/option.dart';
import 'package:litechron/page/option/option_controller.dart';
import 'package:litechron/page/scholar/scholar_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'support/refresh_fakes.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  for (final retryFails in [false, true]) {
    testWidgets('补刷${retryFails ? '失败' : '成功'}：加载持续至最终结束，清除上一轮播报',
        (tester) async {
      final fixture = RefreshFixture();
      Get.put(fixture.scholar.obs, tag: 'scholar');
      Get.put<Option>(refreshOptions(), tag: 'option');
      Get.put<OptionController>(RefreshOptionController(),
          tag: 'optionController');
      final controller = ScholarController();
      addTearDown(controller.onClose);

      final automatic = fixture.scholar.refresh();
      final first = await fixture.spider.fetchAt(0);
      first.emit(fetchResult(errors: [
        for (final label in fetchLabels) label == '作业' ? null : '$label查询进行中',
      ]));
      var completed = false;
      final manual = controller.fetchData();
      final concurrent = controller.fetchData();
      unawaited(manual.then((_) => completed = true));
      await tester.pump(const Duration(seconds: 5));
      expect(controller.refreshStatusMessage.value, contains('正在'));

      // 展示提示后首轮才失败，此时会产生待播报的成功/失败消息。
      first.emit(fetchResult(errors: academicErrors));
      first.result.complete(
          fetchResult(errors: academicErrors, todos: [sampleTodo('first')]));
      await tester.pump();
      final retry = await fixture.spider.fetchAt(1);
      final joinedDuringRetry = controller.fetchData();
      expect(completed, isFalse);
      expect(controller.refreshStatusMessage.value, contains('正在'));
      await tester.pump(const Duration(milliseconds: 2500));
      expect(controller.refreshStatusMessage.value, contains('正在'));
      expect(controller.refreshStatusMessage.value, isNot(contains('失败')));
      expect(fixture.scholar.lastUpdateTimeGrade, oldUpdateTime);

      retry.result.complete(fetchResult(
          errors: retryFails ? academicErrors : null,
          todos: [sampleTodo('retry')]));
      await tester.pump();
      final results = await Future.wait([
        automatic,
        manual,
        concurrent,
        joinedDuringRetry,
      ]);
      for (final result in results) {
        expect(result, retryFails ? academicErrors : everyElement(isNull));
      }
      expect(completed, isTrue);
      expect(fixture.spider.interactionRequests, [false, true]);
      expect(controller.refreshStatusMessage.value, isNull);
      expect(fixture.scholar.lastUpdateTimeGrade.isAfter(oldUpdateTime),
          !retryFails);
      expect(fixture.scholar.lastUpdateTimeCourse.isAfter(oldUpdateTime),
          !retryFails);
      await tester.pump(const Duration(seconds: 10));
      expect(controller.refreshStatusMessage.value, isNull);
    });
  }
}
