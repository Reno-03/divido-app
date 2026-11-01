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
    expect(find.text('12%'), findsNWidgets(2));
    expect(find.byTooltip('12% vs last week'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero settle ring displays 0, 50, and 100 percent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget hero(double settledAmount) {
      return MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: DashHeroBalance(
                owedToYou: 327,
                youOwe: 0,
                settledAmount: settledAmount,
                totalGroupAmount: 100,
                onSettle: () {},
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(hero(0));
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Owed to you'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(hero(50));
    expect(find.text('50%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(hero(100));
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settled hero shows the empty state instead of an amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashHeroBalance(
            owedToYou: 0,
            youOwe: 0,
            settledAmount: 100,
            totalGroupAmount: 100,
            onSettle: _noop,
          ),
        ),
      ),
    );

    expect(find.text('All settled up!'), findsOneWidget);
    expect(find.textContaining('327'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
