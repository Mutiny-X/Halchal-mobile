import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/format/money_format.dart';
import '../../core/layout/app_spacing.dart';
import '../../core/widgets/retry_error_view.dart';
import '../../core/widgets/vc_scaffold.dart';
import '../../theme/halchal_colors.dart';
import 'wallet_providers.dart';
import 'withdrawal_state.dart';

final payoutMethodsProvider = FutureProvider<List<PayoutMethod>>((ref) async {
  return ref.read(apiClientProvider).fetchPayoutMethods();
});

class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  int? _amountPaise;
  String? _methodId;
  bool _loading = false;

  /// One key per withdrawal attempt, reused if the same request is retried
  /// (e.g. the connection dropped after the server saved it) so a retry can
  /// never create a second withdrawal. Cleared when the creator changes the
  /// amount or method, and after a success.
  String? _attemptKey;

  void _pickAmount(int amountPaise) {
    setState(() {
      _amountPaise = amountPaise;
      _attemptKey = null;
    });
  }

  void _pickMethod(String id) {
    setState(() {
      _methodId = id;
      _attemptKey = null;
    });
  }

  Future<void> _submit(WithdrawalRules rules) async {
    final amount = _amountPaise;
    final methodId = _methodId;
    if (amount == null || methodId == null) return;
    setState(() => _loading = true);
    _attemptKey ??= 'wd-${DateTime.now().microsecondsSinceEpoch}-$amount-$methodId';
    try {
      final result = await ref.read(apiClientProvider).createWithdrawal(
            amountPaise: amount,
            payoutMethodId: methodId,
            idempotencyKey: _attemptKey,
          );
      _attemptKey = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Withdrawal requested — ${formatPaise(result.netPaise)} will reach you within ${rules.expectedDays} days.',
          ),
        ),
      );
      ref.invalidate(walletProvider);
      ref.invalidate(walletTransactionsProvider);
      ref.invalidate(withdrawalsProvider);
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      // The rules may have changed under us (e.g. a request already open) —
      // refresh so the screen explains why instead of just failing again.
      ref.invalidate(walletProvider);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final methods = ref.watch(payoutMethodsProvider);

    return VcScaffold(
      title: 'Withdraw',
      showBack: true,
      body: wallet.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetryErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(walletProvider),
        ),
        data: (w) => methods.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RetryErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(payoutMethodsProvider),
          ),
          data: (list) => _buildBody(context, w, list),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WalletData w, List<PayoutMethod> list) {
    final vc = HalchalColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final rules = w.withdrawal;
    final availability = withdrawalAvailability(rules);

    if (list.isNotEmpty && _methodId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _methodId == null) setState(() => _methodId = list.first.id);
      });
    }

    final amount = _amountPaise;
    // An amount picked earlier may no longer be valid (balance changed).
    final amountStillValid = amount != null &&
        rules.denominationsPaise.contains(amount) &&
        amount <= w.availablePaise;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
        AppSpacing.screenHorizontal,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Balance card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: vc.deepSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available balance',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 6),
                Text(
                  formatPaise(w.availablePaise),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: vc.moneyBright,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (!availability.canWithdraw) ...[
            _NoticeCard(
              key: const Key('withdraw-notice'),
              block: availability.block,
              message: availability.message,
              lifetimePaise: w.lifetimePaise,
              gatePaise: rules.lifetimeGatePaise,
            ),
            if (availability.block == WithdrawalBlock.openRequest ||
                availability.block == WithdrawalBlock.dailyLimit) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.go('/wallet'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('See my withdrawals'),
                ),
              ),
            ],
          ] else ...[
            // Amount picker — fixed amounts only, no free typing.
            Text(
              'CHOOSE AMOUNT',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: vc.muted,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in withdrawalOptions(rules, w.availablePaise))
                  ChoiceChip(
                    key: Key('amount-${o.amountPaise}'),
                    label: Text(formatPaise(o.amountPaise)),
                    selected: amountStillValid && amount == o.amountPaise,
                    onSelected: o.affordable ? (_) => _pickAmount(o.amountPaise) : null,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: o.affordable ? vc.onSurface : vc.muted.withValues(alpha: 0.5),
                    ),
                    backgroundColor: vc.surface,
                    side: BorderSide(color: vc.border),
                  ),
              ],
            ),
            if (!withdrawalOptions(rules, w.availablePaise).any((o) => o.affordable)) ...[
              const SizedBox(height: 10),
              Text(
                'Your available balance is below the smallest withdrawal '
                '(${formatPaise(rules.denominationsPaise.first)}).',
                key: const Key('below-minimum'),
                style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: vc.muted),
              ),
            ],
            const SizedBox(height: 24),

            if (list.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PAY TO',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: vc.muted,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context
                        .push('/wallet/bank-details')
                        .then((_) => ref.invalidate(payoutMethodsProvider)),
                    child: Text(
                      'Manage',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...list.map((m) => _PayoutMethodTile(
                    method: m,
                    selected: _methodId == m.id,
                    onTap: () => _pickMethod(m.id),
                  )),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: vc.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: vc.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_outlined, color: vc.primary, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Add your bank details',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: vc.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Money can only be withdrawn to a bank account — add yours (with PAN) to continue.',
                      style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: vc.muted),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context
                            .push('/wallet/bank-details')
                            .then((_) => ref.invalidate(payoutMethodsProvider)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Add bank details'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            if (amountStillValid) ...[
              _SummaryTable(
                amountPaise: amount,
                feePaise: rules.feeFor(amount),
                netPaise: rules.netFor(amount),
                feeLabel: _feeLabel(rules.feeBps),
              ),
              const SizedBox(height: 10),
              Text(
                'Paid to your account within ${rules.expectedDays} days of your request. '
                'If a payment can\'t be made, the full amount returns to your wallet.',
                key: const Key('payment-timeline'),
                style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: vc.muted),
              ),
              const SizedBox(height: 20),
            ],

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('request-withdrawal'),
                onPressed: _loading || _methodId == null || !amountStillValid
                    ? null
                    : () => _submit(rules),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Request withdrawal',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "5%" for 500 bps, "1.5%" for 150 bps.
String _feeLabel(int feeBps) {
  final pct = feeBps / 100;
  final text = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
  return 'Platform fee ($text%)';
}

/// Explains why withdrawing isn't possible right now, with a progress bar
/// towards the unlock threshold when that's the reason.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    super.key,
    required this.block,
    required this.message,
    required this.lifetimePaise,
    required this.gatePaise,
  });

  final WithdrawalBlock block;
  final String message;
  final int lifetimePaise;
  final int gatePaise;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    final icon = switch (block) {
      WithdrawalBlock.locked => Icons.lock_outline_rounded,
      WithdrawalBlock.openRequest => Icons.hourglass_top_rounded,
      WithdrawalBlock.dailyLimit => Icons.event_available_outlined,
      _ => Icons.info_outline_rounded,
    };
    final title = switch (block) {
      WithdrawalBlock.locked => 'Withdrawals are locked',
      WithdrawalBlock.openRequest => 'Withdrawal in progress',
      WithdrawalBlock.dailyLimit => 'One withdrawal per day',
      _ => 'Withdrawals unavailable',
    };
    final progress = gatePaise > 0 ? (lifetimePaise / gatePaise).clamp(0.0, 1.0) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: vc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: vc.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: vc.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: vc.muted),
          ),
          if (block == WithdrawalBlock.locked && gatePaise > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: vc.border,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatPaise(lifetimePaise)} of ${formatPaise(gatePaise)} earned',
              style: GoogleFonts.inter(fontSize: 11, color: vc.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayoutMethodTile extends StatelessWidget {
  const _PayoutMethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PayoutMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.06) : vc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : vc.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              method.type == 'upi' || method.label.toLowerCase().contains('upi')
                  ? Icons.phone_android
                  : Icons.account_balance,
              size: 20,
              color: selected ? primary : vc.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: vc.onSurface,
                    ),
                  ),
                  Text(
                    method.accountMasked,
                    style: GoogleFonts.inter(fontSize: 12, color: vc.muted),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable({
    required this.amountPaise,
    required this.feePaise,
    required this.netPaise,
    required this.feeLabel,
  });

  final int amountPaise;
  final int feePaise;
  final int netPaise;
  final String feeLabel;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: vc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vc.border),
      ),
      child: Column(
        children: [
          _Row(label: 'Amount', value: formatPaise(amountPaise), vc: vc),
          const SizedBox(height: 8),
          _Row(
            label: feeLabel,
            value: '- ${formatPaise(feePaise)}',
            vc: vc,
            valueColor: vc.muted,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: vc.border),
          ),
          _Row(
            label: 'You receive',
            value: formatPaise(netPaise),
            vc: vc,
            bold: true,
            valueColor: vc.money,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.vc,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final HalchalColors vc;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: vc.muted)),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? vc.onSurface,
          ),
        ),
      ],
    );
  }
}
