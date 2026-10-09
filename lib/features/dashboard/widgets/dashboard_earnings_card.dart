import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../core/format/money_format.dart';
import '../../../theme/halchal_colors.dart';
import '../../wallet/withdrawal_state.dart';

class DashboardEarningsCard extends StatelessWidget {
  const DashboardEarningsCard({
    super.key,
    required this.wallet,
    required this.clipsUnderReview,
    required this.onWithdraw,
  });

  final WalletData wallet;
  final int clipsUnderReview;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    final onDark = vc.onPrimary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: vc.deepSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded,
                            size: 13, color: onDark.withValues(alpha: 0.62)),
                        const SizedBox(width: 5),
                        Text(
                          'Total earned',
                          style: GoogleFonts.inter(
                            color: onDark.withValues(alpha: 0.62),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatPaise(wallet.lifetimePaise),
                      style: GoogleFonts.plusJakartaSans(
                        color: vc.moneyBright,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ).animate(onPlay: (controller) => controller.repeat(reverse: true)).shimmer(
                          duration: 2500.ms,
                          color: onDark.withValues(alpha: 0.36),
                        ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: onDark.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Pending',
                  value: formatPaise(wallet.pendingPaise),
                  valueColor: vc.moneyBright,
                  subtitle: 'Will be available soon',
                  icon: Icons.access_time,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _MetricTile(
                  label: 'Clips under review',
                  value: clipsUnderReview.toString(),
                  valueColor: vc.primary,
                  subtitle: 'View clips',
                  icon: Icons.video_library_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _WithdrawButton(
            onPressed: onWithdraw,
            onDark: onDark,
            rules: wallet.withdrawal,
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.subtitle,
    required this.icon,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final onDark = HalchalColors.of(context).onPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          style: GoogleFonts.inter(
            color: onDark.withValues(alpha: 0.62),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            color: valueColor,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: onDark.withValues(alpha: 0.52), size: 13),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                subtitle,
                maxLines: 2,
                style: GoogleFonts.inter(
                  color: onDark.withValues(alpha: 0.56),
                  fontSize: 10,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WithdrawButton extends StatelessWidget {
  const _WithdrawButton({
    required this.onPressed,
    required this.onDark,
    required this.rules,
  });

  final VoidCallback onPressed;
  final Color onDark;
  final WithdrawalRules rules;

  @override
  Widget build(BuildContext context) {
    final availability = withdrawalAvailability(rules);
    final canWithdraw = availability.canWithdraw;
    return Material(
      color: onDark.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      // Always opens the Withdraw screen: it explains any block in full.
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: canWithdraw ? 1 : 0.7,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.account_balance_outlined, color: onDark, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Withdraw',
                        style: GoogleFonts.inter(
                          color: onDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        withdrawSubtitle(rules),
                        style: GoogleFonts.inter(
                          color: onDark.withValues(alpha: 0.62),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  availability.block == WithdrawalBlock.locked
                      ? Icons.lock_outline_rounded
                      : Icons.arrow_forward_rounded,
                  color: onDark,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}