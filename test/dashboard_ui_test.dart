import 'package:divido_app/widgets/dashboard_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stat tiles fit a narrow screen and show trend chips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: DashStatTile(
                    icon: Icons.groups_rounded,
                    label: 'Group expenses',
                    value: 1234.5,
                    changePct: 12,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: DashStatTile(
                    icon: Icons.person_rounded,
                    label: 'Your expenses',
                    value: 234.5,
                    changePct: -12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Group expenses'), findsOneWidget);
    expect(find.text('Your expenses'), findsOneWidget);
    expect(find.text('12% vs last week'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('balance hero shows the owed amount and keeps its action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var actionPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: DashHeroBalance(
                owedToYou: 327,
                youOwe: 0,
                actionLabel: 'View balances',
                onSettle: () => actionPressed = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('GROUP BALANCE'), findsOneWidget);
    expect(find.text("You're owed"), findsOneWidget);
    expect(find.text('Nudge them to settle'), findsOneWidget);
    expect(find.textContaining('327'), findsNWidgets(2));
    await tester.tap(find.text('View balances'));
    expect(actionPressed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settled hero shows its settled state', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: DashHeroBalance(owedToYou: 0, youOwe: 0, onSettle: _noop),
            ),
          ),
        ),
      ),
    );

    expect(find.text('All settled'), findsOneWidget);
    expect(find.text('No pending balances in this group'), findsOneWidget);
    expect(find.text('View balances'), findsOneWidget);
    expect(find.textContaining('327'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
