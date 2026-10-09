import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:viralcut_mobile/core/api/api_client.dart';
import 'package:viralcut_mobile/features/wallet/wallet_providers.dart';
import 'package:viralcut_mobile/features/wallet/withdraw_screen.dart';
import 'package:viralcut_mobile/theme/halchal_theme.dart';

const _denominations = [
  50000, 100000, 300000, 500000, 1000000, 1500000, 2000000, 2500000,
  3000000, 3500000, 4000000, 4500000, 5000000,
];

WithdrawalRules _rules({
  bool unlocked = true,
  int remaining = 0,
  bool open = false,
  bool today = false,
}) =>
    WithdrawalRules(
      unlocked: unlocked,
      lifetimeGatePaise: 150000,
      remainingToUnlockPaise: remaining,
      denominationsPaise: _denominations,
      feeBps: 500,
      hasOpenWithdrawal: open,
      requestedToday: today,
      expectedDays: 7,
    );

final _method = PayoutMethod(
  id: 'pm-1',
  type: 'bank',
  label: 'HDFC Bank',
  accountHolderName: 'Ravi Kumar',
  accountMasked: '•••• 7890',
  isDefault: true,
);

Future<void> _pump(
  WidgetTester tester, {
  required WalletData wallet,
  List<PayoutMethod>? methods,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        walletProvider.overrideWith((ref) async => wallet),
        payoutMethodsProvider.overrideWith((ref) async => methods ?? [_method]),
      ],
      child: MaterialApp(theme: HalchalTheme.light, home: const WithdrawScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    // Never reach for the network from a test.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('locked below the gate: explains why, shows progress, offers no amounts', (tester) async {
    await _pump(
      tester,
      wallet: WalletData(
        availablePaise: 100000,
        pendingPaise: 0,
        lifetimePaise: 100000,
        withdrawal: _rules(unlocked: false, remaining: 50000),
      ),
    );
    expect(find.text('Withdrawals are locked'), findsOneWidget);
    expect(find.textContaining('₹1,500'), findsWidgets);
    expect(find.textContaining('₹500 away'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const Key('request-withdrawal')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('an open withdrawal blocks a new one and points to the status', (tester) async {
    await _pump(
      tester,
      wallet: WalletData(
        availablePaise: 1000000,
        pendingPaise: 0,
        lifetimePaise: 2000000,
        withdrawal: _rules(open: true),
      ),
    );
    expect(find.text('Withdrawal in progress'), findsOneWidget);
    expect(find.text('See my withdrawals'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('one per day: says come back tomorrow', (tester) async {
    await _pump(
      tester,
      wallet: WalletData(
        availablePaise: 1000000,
        pendingPaise: 0,
        lifetimePaise: 2000000,
        withdrawal: _rules(today: true),
      ),
    );
    expect(find.text('One withdrawal per day'), findsOneWidget);
    expect(find.textContaining('tomorrow'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('an older API with no rules keeps withdrawals unavailable', (tester) async {
    await _pump(
      tester,
      wallet: WalletData(availablePaise: 1000000, pendingPaise: 0, lifetimePaise: 2000000),
    );
    expect(find.text('Withdrawals unavailable'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('unlocked: fixed amounts only, unaffordable ones disabled, no typing', (tester) async {
    await _pump(
      tester,
      wallet: WalletData(
        availablePaise: 350000,
        pendingPaise: 0,
        lifetimePaise: 2000000,
        withdrawal: _rules(),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(13));

    ChoiceChip chip(int paise) => tester.widget<ChoiceChip>(find.byKey(Key('amount-$paise')));
    expect(chip(50000).onSelected, isNotNull); // ₹500
    expect(chip(300000).onSelected, isNotNull); // ₹3,000
    expect(chip(500000).onSelected, isNull); // ₹5,000 > ₹3,500 balance
    expect(chip(5000000).onSelected, isNull);
  });

  testWidgets('picking an amount shows the server fee, what they receive, and the timeline', (tester) async {
    await _pump(
      tester,
      wallet: WalletData(
        availablePaise: 2000000,
        pendingPaise: 0,
        lifetimePaise: 2000000,
        withdrawal: _rules(),
      ),
    );

    // Nothing selected yet: no summary, button disabled.
    expect(find.text('You receive'), findsNothing);
    FilledButton button() => tester.widget<FilledButton>(find.byKey(const Key('request-withdrawal')));
    expect(button().onPressed, isNull);

    await tester.tap(find.byKey(const Key('amount-100000'))); // ₹1,000
    await tester.pumpAndSettle();

    expect(find.text('Platform fee (5%)'), findsOneWidget);
    expect(find.text('- ₹50'), findsOneWidget);
    expect(find.text('₹950'), findsOneWidget); // you receive
    expect(find.byKey(const Key('payment-timeline')), findsOneWidget);
    expect(find.textContaining('within 7 days'), findsOneWidget);
    expect(button().onPressed, isNotNull);
  });

  testWidgets('a balance under the smallest amount says so and offers nothing affordable', (tester) async {
    await _pump(
      tester,
      wallet: WalletData(
        availablePaise: 30000,
        pendingPaise: 0,
        lifetimePaise: 2000000,
        withdrawal: _rules(),
      ),
    );
    expect(find.byKey(const Key('below-minimum')), findsOneWidget);
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(chips.every((c) => c.onSelected == null), isTrue);
  });

  testWidgets('with no payout method yet, prompts to add bank details and cannot submit', (tester) async {
    await _pump(
      tester,
      methods: const [],
      wallet: WalletData(
        availablePaise: 2000000,
        pendingPaise: 0,
        lifetimePaise: 2000000,
        withdrawal: _rules(),
      ),
    );
    expect(find.text('Add your bank details'), findsOneWidget);
    await tester.tap(find.byKey(const Key('amount-100000')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('request-withdrawal'))).onPressed, isNull);
  });
}
