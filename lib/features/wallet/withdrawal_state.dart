import '../../core/api/api_client.dart';
import '../../core/format/money_format.dart';

/// Why a creator can't withdraw right now — or [none] when they can.
/// Derived entirely from the server's [WithdrawalRules]; nothing here knows the
/// ₹1,500 gate or the amounts itself.
enum WithdrawalBlock { none, rulesUnavailable, locked, openRequest, dailyLimit }

class WithdrawalAvailability {
  const WithdrawalAvailability(this.block, this.message);

  final WithdrawalBlock block;

  /// Shown to the creator when [block] isn't [WithdrawalBlock.none].
  final String message;

  bool get canWithdraw => block == WithdrawalBlock.none;
}

WithdrawalAvailability withdrawalAvailability(WithdrawalRules rules) {
  if (rules.denominationsPaise.isEmpty) {
    return const WithdrawalAvailability(
      WithdrawalBlock.rulesUnavailable,
      'Withdrawals aren\'t available right now. Please try again shortly.',
    );
  }
  if (!rules.unlocked) {
    return WithdrawalAvailability(
      WithdrawalBlock.locked,
      'Withdrawals unlock once your total earnings reach ${formatPaise(rules.lifetimeGatePaise)}. '
      'You\'re ${formatPaise(rules.remainingToUnlockPaise)} away.',
    );
  }
  if (rules.hasOpenWithdrawal) {
    return const WithdrawalAvailability(
      WithdrawalBlock.openRequest,
      'You already have a withdrawal in progress. You can request another once it has been paid.',
    );
  }
  if (rules.requestedToday) {
    return const WithdrawalAvailability(
      WithdrawalBlock.dailyLimit,
      'You\'ve already requested a withdrawal today. Come back tomorrow.',
    );
  }
  return const WithdrawalAvailability(WithdrawalBlock.none, '');
}

/// The short line under the "Withdraw" entry points (Wallet and Dashboard) -
/// says why withdrawing is blocked when it is.
String withdrawSubtitle(WithdrawalRules rules) {
  final availability = withdrawalAvailability(rules);
  return switch (availability.block) {
    WithdrawalBlock.none => 'Transfer to bank',
    WithdrawalBlock.locked => 'Unlocks at ${formatPaise(rules.lifetimeGatePaise)}',
    WithdrawalBlock.openRequest => 'In progress',
    WithdrawalBlock.dailyLimit => 'Back tomorrow',
    WithdrawalBlock.rulesUnavailable => 'Unavailable',
  };
}

/// Denominations the creator can pick right now, with whether each fits within
/// their available balance.
List<({int amountPaise, bool affordable})> withdrawalOptions(
  WithdrawalRules rules,
  int availablePaise,
) =>
    [
      for (final d in rules.denominationsPaise)
        (amountPaise: d, affordable: d <= availablePaise),
    ];

/// Creator-facing label for a withdrawal status. "processing" is internal
/// jargon (it means the request is with the accounts team), so creators just
/// see that it's being processed.
String withdrawalStatusLabel(String status) => switch (status) {
      'pending' => 'Requested',
      'processing' => 'Processing',
      'completed' => 'Paid',
      'failed' => 'Failed — refunded',
      _ => status,
    };

/// How a ledger row should read: its label and whether it adds to the balance.
/// Amounts are always stored positive, so direction comes from the type.
({String label, bool isCredit}) transactionPresentation(String type, int amountPaise) =>
    switch (type) {
      'earning' || 'earning_credit' => (label: 'Campaign earning', isCredit: true),
      'withdrawal' || 'withdrawal_debit' => (label: 'Withdrawal', isCredit: false),
      'withdrawal_refund' || 'refund' => (label: 'Withdrawal refunded', isCredit: true),
      'fee_debit' => (label: 'Fee', isCredit: false),
      'bonus' => (label: 'Bonus', isCredit: true),
      'adjustment' => (label: 'Adjustment', isCredit: amountPaise >= 0),
      _ => (label: type, isCredit: amountPaise > 0),
    };
