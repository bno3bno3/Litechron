import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litechron/page/task/task_swipe_card.dart';

class _Fixture {
  final controller = TaskSwipeController();
  int deletes = 0;
  int toggles = 0;
  int edits = 0;
  bool completed = false;
  bool fixed = false;

  Widget card(String uid) => TaskSwipeCard(
        key: ValueKey('swipe-$uid'),
        uid: uid,
        taskLabel: '任务$uid',
        controller: controller,
        isCompleted: completed,
        onTap: () => edits++,
        onDelete: () => deletes++,
        onToggleComplete: fixed ? null : () => toggles++,
        child: SizedBox(
          key: ValueKey('body-$uid'),
          height: 120,
          width: double.infinity,
          child: const ColoredBox(color: CupertinoColors.white),
        ),
      );

  Widget app({double scale = 1, bool reduceMotion = false}) => CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: TaskSwipeRegion(
          controller: controller,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              card('a'),
              const SizedBox(height: 16),
              card('b'),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      );
}

Finder _card(String uid) => find.byKey(ValueKey('swipe-$uid'));

Future<void> _swipe(WidgetTester tester, String uid, double distance,
    {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
  await tester.drag(_card(uid), Offset(distance, 0), kind: kind);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'short, full-width and fast swipes only reveal; clicking deletes once',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await _swipe(tester, 'a', -30);
    expect(fixture.controller.value, isNull);
    expect(find.text('删除'), findsNothing);

    await tester.fling(_card('a'), const Offset(-600, 0), 2500);
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
    expect(fixture.deletes, 0);
    expect(fixture.edits, 0);
    expect(fixture.toggles, 0);
    expect(tester.getTopLeft(find.byKey(const ValueKey('body-a'))).dx,
        tester.getTopLeft(_card('a')).dx - 80);

    final deletePosition = tester.getCenter(find.text('删除'));
    await tester.tapAt(deletePosition);
    await tester.tapAt(deletePosition);
    await tester.pumpAndSettle();
    expect(fixture.deletes, 1);
    expect(fixture.controller.value, isNull);
  });

  testWidgets('completion and restore require their own button click',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await _swipe(tester, 'a', 160);
    expect(find.text('完成'), findsOneWidget);
    expect(fixture.toggles, 0);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(fixture.toggles, 1);

    fixture.completed = true;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _swipe(tester, 'a', 160);
    expect(find.text('恢复'), findsOneWidget);
    expect(fixture.toggles, 1);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(fixture.toggles, 2);
    expect(fixture.deletes, 0);
  });

  testWidgets('actions cannot run while dragging or during snap animation',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    final finger = await tester.startGesture(tester.getCenter(_card('a')));
    await finger.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(find.text('删除'), findsOneWidget);
    final deletePosition = tester.getCenter(find.text('删除'));
    await tester.tapAt(deletePosition);
    await tester.pump();
    expect(fixture.deletes, 0);
    await finger.up();
    await tester.pumpAndSettle();

    await _swipe(tester, 'a', 200);
    fixture.controller.close();
    await tester.pumpAndSettle();
    await tester.drag(_card('a'), const Offset(-60, 0));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.text('删除')));
    await tester.pumpAndSettle();
    expect(fixture.deletes, 0);
  });

  testWidgets('a body tap closes any open card before the next tap edits',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await _swipe(tester, 'a', -140);
    await tester.tap(find.byKey(const ValueKey('body-a')));
    await tester.pumpAndSettle();
    expect(fixture.edits, 0);
    expect(find.text('删除'), findsNothing);
    await tester.tap(_card('a'));
    expect(fixture.edits, 1);

    await _swipe(tester, 'a', -140);
    await tester.tap(_card('b'));
    await tester.pumpAndSettle();
    expect(fixture.edits, 1);
    expect(fixture.controller.value, isNull);
    await tester.tap(_card('b'));
    expect(fixture.edits, 2);
  });

  testWidgets('another swipe, background tap and vertical scroll close actions',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await _swipe(tester, 'a', -140);
    await _swipe(tester, 'b', -140);
    expect(fixture.controller.value, 'b');
    expect(find.text('删除'), findsOneWidget);

    await tester.tapAt(const Offset(400, 400));
    await tester.pumpAndSettle();
    expect(fixture.controller.value, isNull);

    await _swipe(tester, 'a', -140);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(fixture.controller.value, isNull);
    expect(fixture.deletes + fixture.toggles + fixture.edits, 0);
  });

  testWidgets('reverse drags close without revealing the opposite action',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await _swipe(tester, 'a', -120);
    await _swipe(tester, 'a', 300);
    expect(find.text('完成'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(fixture.controller.value, isNull);
    await _swipe(tester, 'a', 120);
    expect(find.text('完成'), findsOneWidget);
    expect(fixture.deletes + fixture.toggles, 0);
  });

  testWidgets(
      'fixed schedule right drag reaches PageView; left drag stays on card',
      (tester) async {
    final fixture = _Fixture()..fixed = true;
    final pages = PageController(initialPage: 1);
    await tester.pumpWidget(CupertinoApp(
      home: PageView(
        controller: pages,
        children: [
          const Center(child: Text('上一页')),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: fixture.card('a'),
            ),
          ),
        ],
      ),
    ));
    await _swipe(tester, 'a', -200);
    expect(pages.page, 1);
    expect(find.text('删除'), findsOneWidget);
    await _swipe(tester, 'a', 200);
    expect(pages.page, 1);
    expect(fixture.controller.value, isNull);
    await _swipe(tester, 'a', 600);
    expect(pages.page, 0);
    expect(fixture.deletes + fixture.toggles, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    pages.dispose();
  });

  testWidgets(
      'regular rebuild preserves reveal; changed task identity resets it',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await _swipe(tester, 'a', -120);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.controller.value, 'a');
    expect(find.text('删除'), findsOneWidget);
    fixture.completed = true;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.controller.value, isNull);
    expect(find.text('删除'), findsNothing);
  });

  testWidgets('mouse, large text and reduced motion support explicit actions',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app(scale: 2, reduceMotion: true));
    await _swipe(tester, 'a', -180, kind: PointerDeviceKind.mouse);
    final semantics = tester.ensureSemantics();
    expect(
        tester.getSemantics(find.bySemanticsLabel('删除任务：任务a')),
        matchesSemantics(
          label: '删除任务：任务a',
          isButton: true,
          hasTapAction: true,
        ));
    final button = find.widgetWithText(CupertinoButton, '删除');
    expect(tester.getSize(button).width, greaterThanOrEqualTo(80));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(fixture.deletes, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
