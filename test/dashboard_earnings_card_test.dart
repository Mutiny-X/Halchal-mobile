import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:viralcut_mobile/core/api/api_client.dart';
import 'package:viralcut_mobile/features/dashboard/widgets/dashboard_earnings_card.dart';
import 'package:viralcut_mobile/theme/halchal_theme.dart';

WithdrawalRules _rules({
  bool unlocked = true,
  int remaining = 0,
  bool open = false,
}) =>
    WithdrawalRules(
      unlocked: unlocked,
      lifetimeGatePaise: 150000,
      remainingToUnlockPaise: remaining,
      denominationsPaise: const [50000, 100000, 300000],
      feeBps: 500,
      hasOpenWithdrawal: open,
      requestedToday: false,
      expectedDays: 7,
    );

Future<int> _pumpAndTap(WidgetTester tester, WithdrawalRules rules) async {
  var taps = 0;
  GoogleFonts.config.allowRuntimeFetching = false;
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: HalchalTheme.light,
      home: Scaffold(
        body: DashboardEarningsCard(
          wallet: WalletData(
            availablePaise: 2000000,
            pendingPaise: 0,
            lifetimePaise: 2000000,
            withdrawal: rules,
          ),
          clipsUnderReview: 0,
          onWithdraw: () => taps++,
        ),
      ),
    ),
  );
  // The earnings figure shimmers forever, so settle with a plain pump.
  await tester.pump();
  await tester.tap(find.text('Withdraw'));
  await tester.pump();
  return taps;
}

// Dispose the tree and let flutter_animate's zero-length timer fire, so the
// test doesn't end with a pending timer.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('unlocked: Withdraw opens the withdraw screen', (tester) async {
    expect(await _pumpAndTap(tester, _rules()), 1);
    expect(find.text('Transfer to bank'), findsOneWidget);
    expect(find.text('Processed manually for now'), findsNothing);
    await _finish(tester);
  });

  testWidgets('locked: still navigates, and says when it unlocks', (tester) async {
    expect(await _pumpAndTap(tester, _rules(unlocked: false, remaining: 50000)), 1);
    expect(find.text('Unlocks at ₹1,500'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('open request: shows In progress', (tester) async {
    expect(await _pumpAndTap(tester, _rules(open: true)), 1);
    expect(find.text('In progress'), findsOneWidget);
    await _finish(tester);
  });
}
