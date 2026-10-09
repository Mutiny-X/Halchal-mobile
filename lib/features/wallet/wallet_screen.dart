import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/format/money_format.dart';
import '../../core/layout/app_spacing.dart';
import '../../core/layout/list_entrance.dart';
import '../../core/widgets/retry_error_view.dart';
import '../../theme/halchal_colors.dart';
import 'wallet_providers.dart';
import 'withdrawal_state.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final transactions = ref.watch(walletTransactionsProvider);
    final withdrawals = ref.watch(withdrawalsProvider);

    return wallet.when(
      skipLoadingOnRefresh: true,
      loading: () => const ScreenLoader(),
      error: (e, _) => RetryErrorView(
        message: '$e',
        onRetry: () {
          ref.invalidate(walletProvider);
          ref.invalidate(walletTransactionsProvider);
          ref.invalidate(withdrawalsProvider);
        },
      ),
      data: (w) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(walletProvider);
            ref.invalidate(walletTransactionsProvider);
            ref.invalidate(withdrawalsProvider);
          },
          child: ScreenStaggeredColumn(
            animationKey: 'wallet',
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.sm,
              AppSpacing.screenHorizontal,
              AppSpacing.floatingNavBottom(context),
            ),
            children: [
              _BalanceCard(
                wallet: w,
                clipsUnderReview: w.clipsUnderReview,
                onWithdraw: () => context.push('/withdraw'),
                onViewClips: () => context.go('/submissions'),
              ),
              const SizedBox(height: 16),
              _EarningsOverview(wallet: w),
              const SizedBox(height: 24),
              _WithdrawalsSection(
                withdrawals: withdrawals,
                expectedDays: w.withdrawal.expectedDays,
                onRetry: () => ref.invalidate(withdrawalsProvider),
              ),
              const SizedBox(height: 24),
              _TransactionSection(
                transactions: transactions,
                onRetry: () => ref.invalidate(walletTransactionsProvider),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.wallet,
    required this.clipsUnderReview,
    required this.onWithdraw,
    required this.onViewClips,
  });

  final WalletData wallet;
  final int clipsUnderReview;
  final VoidCallback onWithdraw;
  final VoidCallback onViewClips;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);

    return Container(
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
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 10),
          // What the creator can withdraw right now. Lifetime earnings are
          // shown separately in the Earnings overview tiles below.
          Text(
            formatPaise(wallet.availablePaise),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: vc.moneyBright,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 16),
          // Bottom 3-column row
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Col 1: Pending
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatPaise(wallet.pendingPaise),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: vc.moneyBright,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 11, color: Colors.white38),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Available soon',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                VerticalDivider(color: Colors.white.withValues(alpha: 0.1), width: 24),
                // Col 2: Clips under review
                Expanded(
                  child: GestureDetector(
                    onTap: onViewClips,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$clipsUnderReview',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: vc.primary,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Clips under review',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right_rounded, size: 13, color: Colors.white38),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(color: Colors.white.withValues(alpha: 0.1), width: 24),
                // Col 3: Withdraw
                Expanded(
                  child: GestureDetector(
                    onTap: onWithdraw,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Withdraw',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                withdrawSubtitle(wallet.withdrawal),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.white54),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsOverview extends StatelessWidget {
  const _EarningsOverview({required this.wallet});

  final WalletData wallet;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EARNINGS OVERVIEW',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: vc.muted,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatBox(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Total earned',
                value: formatPaise(wallet.lifetimePaise),
                valueColor: vc.money,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatBox(
                icon: Icons.check_circle_outline_rounded,
                label: 'Available',
                value: formatPaise(wallet.availablePaise),
                valueColor: vc.onSurface,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatBox(
                icon: Icons.schedule_rounded,
                label: 'Pending',
                value: formatPaise(wallet.pendingPaise),
                valueColor: vc.muted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: vc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: vc.muted),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: vc.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalsSection extends StatelessWidget {
  const _WithdrawalsSection({
    required this.withdrawals,
    required this.expectedDays,
    required this.onRetry,
  });

  final AsyncValue<List<Withdrawal>> withdrawals;
  final int expectedDays;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    return withdrawals.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Row(
        children: [
          Expanded(
            child: Text('Could not load withdrawals', style: TextStyle(color: vc.muted)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
      data: (list) {
        // Nothing requested yet - keep the screen uncluttered.
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WITHDRAWALS',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: vc.muted,
              ),
            ),
            const SizedBox(height: 12),
            ...list.take(10).map((w) => _WithdrawalRow(w: w, expectedDays: expectedDays)),
          ],
        );
      },
    );
  }
}

class _WithdrawalRow extends StatelessWidget {
  const _WithdrawalRow({required this.w, required this.expectedDays});

  final Withdrawal w;
  final int expectedDays;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    final (chipColor, chipBg) = switch (w.status) {
      'completed' => (vc.money, vc.money.withValues(alpha: 0.12)),
      'failed' => (vc.error, vc.error.withValues(alpha: 0.12)),
      _ => (vc.primary, vc.primary.withValues(alpha: 0.12)),
    };

    DateTime? created;
    try {
      created = DateTime.parse(w.createdAt).toLocal();
    } catch (_) {}
    final dateStr = created != null ? '${created.day} ${_monthName(created.month)} ${created.year}' : w.createdAt;

    final detail = switch (w.status) {
      'completed' => w.utr != null && w.utr!.isNotEmpty ? 'Reference ${w.utr}' : 'Sent to your account',
      'failed' => w.failureReason != null && w.failureReason!.isNotEmpty
          ? '${w.failureReason} - ${formatPaise(w.amountPaise)} returned to your wallet'
          : '${formatPaise(w.amountPaise)} returned to your wallet',
      _ => 'Expected within $expectedDays days of your request',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: vc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vc.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatPaise(w.netPaise),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: vc.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateStr${w.payoutLabel != null ? ' · ${w.payoutLabel}' : ''}${w.payoutMasked != null ? ' ${w.payoutMasked}' : ''}',
                  style: GoogleFonts.inter(fontSize: 11, color: vc.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: GoogleFonts.inter(fontSize: 12, height: 1.3, color: vc.onSurface.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(20)),
            child: Text(
              w.status == 'failed' ? 'Failed' : withdrawalStatusLabel(w.status),
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: chipColor),
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m];
}

class _TransactionSection extends StatelessWidget {
  const _TransactionSection({required this.transactions, required this.onRetry});

  final AsyncValue<List<TransactionItem>> transactions;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRANSACTION HISTORY',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: vc.muted,
          ),
        ),
        const SizedBox(height: 12),
        transactions.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text('Could not load transactions',
                      style: TextStyle(color: vc.muted)),
                ),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No transactions yet',
                    style: GoogleFonts.inter(color: vc.muted),
                  ),
                ),
              );
            }
            return Column(
              children: list.map((tx) => _TransactionRow(tx: tx)).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx});

  final TransactionItem tx;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    final presentation = transactionPresentation(tx.type, tx.amountPaise);
    final isCredit = presentation.isCredit;
    final label = presentation.label;
    final icon = switch (tx.type) {
      'earning' || 'earning_credit' => Icons.trending_up,
      'withdrawal' || 'withdrawal_debit' => Icons.arrow_upward,
      'withdrawal_refund' || 'refund' => Icons.replay,
      _ => Icons.receipt_outlined,
    };

    DateTime? parsedDate;
    try {
      parsedDate = DateTime.parse(tx.createdAt);
    } catch (_) {}

    final dateStr = parsedDate != null
        ? '${parsedDate.day} ${_month(parsedDate.month)} ${parsedDate.year}'
        : tx.createdAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: vc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vc.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isCredit
                  ? vc.money.withValues(alpha: 0.1)
                  : vc.muted.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: isCredit ? vc.money : vc.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: vc.onSurface,
                  ),
                ),
                // The debit note is an internal ledger line (fee/net in paise);
                // the Withdrawals section above already shows the details.
                if (tx.type != 'withdrawal_debit' &&
                    tx.note != null &&
                    tx.note!.isNotEmpty)
                  Text(
                    tx.note!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: vc.onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  dateStr,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: vc.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}${formatPaise(tx.amountPaise.abs())}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isCredit ? vc.money : vc.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m];
}
