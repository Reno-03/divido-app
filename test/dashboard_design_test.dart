import 'package:divido_app/widgets/dashboard_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page header and summary tiles fit a narrow screen', (
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
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                DashPageHeader(
                  icon: Icons.receipt_long_rounded,
                  title: 'All expenses',
                  subtitle: 'Shared activity in this group',
                  count: 12,
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DashMetricTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Total',
                        amount: 12345.67,
                        caption: '12 expenses',
                        amountColor: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: DashMetricTile(
                        icon: Icons.person_outline,
                        label: 'Your share',
                        amount: 234.5,
                        caption: 'your portion',
                        amountColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('All expenses'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Your share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard spending cards fit a narrow screen', (tester) async {
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

  testWidgets('balance hero shows a settled state and keeps its action', (
    tester,
  ) async {
    var actionPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DashHeroBalance(
                owedToYou: 0,
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
    expect(find.text('All settled'), findsOneWidget);
    expect(find.text('No pending balances in this group'), findsOneWidget);
    await tester.tap(find.text('View balances'));
    expect(actionPressed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
