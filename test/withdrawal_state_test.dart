import 'package:flutter_test/flutter_test.dart';
import 'package:viralcut_mobile/core/api/api_client.dart';
import 'package:viralcut_mobile/features/wallet/withdrawal_state.dart';

const _denominations = [
  50000, 100000, 300000, 500000, 1000000, 1500000, 2000000, 2500000,
  3000000, 3500000, 4000000, 4500000, 5000000,
];

Map<String, dynamic> _rulesJson({
  bool unlocked = true,
  int remaining = 0,
  bool open = false,
  bool today = false,
  String? nextRequestAt,
}) =>
    {
      'unlocked': unlocked,
      'lifetimeGatePaise': 150000,
      'remainingToUnlockPaise': remaining,
      'denominationsPaise': _denominations,
      'feeBps': 500,
      'hasOpenWithdrawal': open,
      'requestedToday': today,
      'nextRequestAt': nextRequestAt,
      'expectedDays': 7,
    };

WithdrawalRules _rules({bool unlocked = true, int remaining = 0, bool open = false, bool today = false}) =>
    WithdrawalRules.fromJson(_rulesJson(unlocked: unlocked, remaining: remaining, open: open, today: today));

void main() {
  group('WalletData.fromJson', () {
    test('reads the withdrawal rules block from the server', () {
      final w = WalletData.fromJson({
        'availablePaise': 1500000,
        'pendingPaise': 0,
        'lifetimePaise': 2000000,
        'clipsUnderReview': 2,
        'withdrawal': _rulesJson(),
      });
      expect(w.availablePaise, 1500000);
      expect(w.clipsUnderReview, 2);
      expect(w.withdrawal.unlocked, isTrue);
      expect(w.withdrawal.denominationsPaise, _denominations);
      expect(w.withdrawal.feeBps, 500);
      expect(w.withdrawal.expectedDays, 7);
    });

    test('an older API with no rules block stays safely locked instead of guessing', () {
      final w = WalletData.fromJson({'availablePaise': 100, 'pendingPaise': 0, 'lifetimePaise': 100});
      expect(w.withdrawal.denominationsPaise, isEmpty);
      expect(withdrawalAvailability(w.withdrawal).block, WithdrawalBlock.rulesUnavailable);
      expect(withdrawalAvailability(w.withdrawal).canWithdraw, isFalse);
    });
  });

  group('fee preview', () {
    test('uses the server fee and floors like the server does', () {
      final r = _rules();
      expect(r.feeFor(500000), 25000); // 5% of ₹5,000
      expect(r.netFor(500000), 475000);
      expect(r.feeFor(1001), 50); // floor(50.05)
    });

    test('is zero when the server sent no fee', () {
      expect(WithdrawalRules.unavailable().feeFor(500000), 0);
    });
  });

  group('withdrawalAvailability', () {
    test('allows a normal unlocked creator', () {
      final a = withdrawalAvailability(_rules());
      expect(a.canWithdraw, isTrue);
      expect(a.block, WithdrawalBlock.none);
    });

    test('locked below the gate says how far away they are', () {
      final a = withdrawalAvailability(_rules(unlocked: false, remaining: 50000));
      expect(a.block, WithdrawalBlock.locked);
      expect(a.message, contains('₹1,500'));
      expect(a.message, contains('₹500'));
    });

    test('an open request blocks another', () {
      expect(withdrawalAvailability(_rules(open: true)).block, WithdrawalBlock.openRequest);
    });

    test('a request today blocks another until tomorrow', () {
      final a = withdrawalAvailability(_rules(today: true));
      expect(a.block, WithdrawalBlock.dailyLimit);
      expect(a.message, contains('tomorrow'));
    });

    test('locked takes priority over the other reasons', () {
      expect(
        withdrawalAvailability(_rules(unlocked: false, remaining: 1, open: true, today: true)).block,
        WithdrawalBlock.locked,
      );
    });
  });

  group('withdrawalOptions', () {
    test('marks amounts above the available balance as not affordable', () {
      final options = withdrawalOptions(_rules(), 350000);
      expect(options.map((o) => o.amountPaise), _denominations);
      expect(options.where((o) => o.affordable).map((o) => o.amountPaise), [50000, 100000, 300000]);
    });

    test('nothing is affordable below the smallest amount', () {
      expect(withdrawalOptions(_rules(), 49999).any((o) => o.affordable), isFalse);
    });

    test('an amount equal to the balance is affordable', () {
      expect(withdrawalOptions(_rules(), 500000).last.affordable, isFalse);
      expect(withdrawalOptions(_rules(), 500000).firstWhere((o) => o.amountPaise == 500000).affordable, isTrue);
    });
  });

  group('labels', () {
    test('creator-facing withdrawal status labels', () {
      expect(withdrawalStatusLabel('pending'), 'Requested');
      expect(withdrawalStatusLabel('processing'), 'Processing');
      expect(withdrawalStatusLabel('completed'), 'Paid');
      expect(withdrawalStatusLabel('failed'), contains('refunded'));
    });

    test('ledger rows read in the right direction', () {
      expect(transactionPresentation('earning_credit', 100).isCredit, isTrue);
      expect(transactionPresentation('withdrawal_debit', 500000).isCredit, isFalse);
      expect(transactionPresentation('withdrawal_debit', 500000).label, 'Withdrawal');
      expect(transactionPresentation('withdrawal_refund', 500000).isCredit, isTrue);
      expect(transactionPresentation('withdrawal_refund', 500000).label, 'Withdrawal refunded');
      expect(transactionPresentation('adjustment', -100).isCredit, isFalse);
    });
  });

  group('Withdrawal.fromJson', () {
    test('parses a pending withdrawal', () {
      final w = Withdrawal.fromJson({
        'id': 'wd-1',
        'amountPaise': 500000,
        'feePaise': 25000,
        'netPaise': 475000,
        'status': 'pending',
        'createdAt': '2026-10-08T10:00:00.000Z',
        'processedAt': null,
        'utr': null,
        'failureReason': null,
        'payoutLabel': 'HDFC Bank',
        'payoutMasked': '•••• 7890',
      });
      expect(w.isOpen, isTrue);
      expect(w.netPaise, 475000);
      expect(w.payoutMasked, '•••• 7890');
    });

    test('a paid withdrawal is no longer open and carries its UTR', () {
      final w = Withdrawal.fromJson({
        'id': 'wd-1',
        'amountPaise': 500000,
        'feePaise': 25000,
        'netPaise': 475000,
        'status': 'completed',
        'createdAt': '2026-10-08T10:00:00.000Z',
        'processedAt': '2026-10-10T10:00:00.000Z',
        'utr': 'UTR123',
      });
      expect(w.isOpen, isFalse);
      expect(w.utr, 'UTR123');
    });

    test('processing counts as open', () {
      final w = Withdrawal.fromJson({
        'id': 'a',
        'amountPaise': 1,
        'feePaise': 0,
        'netPaise': 1,
        'status': 'processing',
        'createdAt': 'x',
      });
      expect(w.isOpen, isTrue);
    });
  });
}
