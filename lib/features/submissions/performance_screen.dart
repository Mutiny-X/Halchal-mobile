import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/retry_error_view.dart';
import '../../core/widgets/vc_scaffold.dart';
import '../../theme/halchal_colors.dart';
import 'submission_providers.dart';

class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({
    super.key,
    required this.participationId,
    required this.deliverableId,
  });

  final String participationId;
  final String deliverableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(participationDetailProvider(participationId));

    // Every automatic background metrics push (and the 5-minute sweep, and
    // the manual refresh button) invalidates this provider, which briefly
    // re-enters a "loading" AsyncValue state even though we already have
    // good data on screen. Checking hasValue first — instead of a plain
    // .when(loading: ...) — keeps showing that last-known data through a
    // routine background refetch, so the screen updates its numbers in
    // place instead of blanking to a full-screen spinner every few
    // minutes. The spinner is reserved for the genuine first load, when
    // there's no value yet at all.
    if (detail.hasValue) {
      final p = detail.value!;
      final deliverable = p.deliverables.firstWhere(
        (d) => d.id == deliverableId,
        orElse: () => p.deliverables.first,
      );
      return VcScaffold(
        title: 'Performance & Earnings',
        showBack: true,
        body: _PerformanceBody(
          participation: p,
          deliverable: deliverable,
          onRefresh: () => ref.invalidate(participationDetailProvider(participationId)),
        ),
      );
    }

    if (detail.hasError) {
      return VcScaffold(
        title: 'Performance & Earnings',
        showBack: true,
        body: RetryErrorView(
          message: '${detail.error}',
          onRetry: () => ref.invalidate(participationDetailProvider(participationId)),
        ),
      );
    }

    return const VcScaffold(
      title: 'Performance & Earnings',
      showBack: true,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _PerformanceBody extends ConsumerStatefulWidget {
  const _PerformanceBody({
    required this.participation,
    required this.deliverable,
    required this.onRefresh,
  });

  final Participation participation;
  final FormatDeliverable deliverable;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_PerformanceBody> createState() => _PerformanceBodyState();
}

class _PerformanceBodyState extends ConsumerState<_PerformanceBody> {
  // Note: this deliberately holds no local override state for the stats
  // themselves (no _localViews/_localReach/etc.) — Flutter reuses this
  // State object across rebuilds rather than recreating it, so any such
  // override would silently keep shadowing widget.deliverable's real,
  // live value forever after a rebuild — including every automatic update
  // (the deliverable:metrics_updated realtime push, or the 5-minute
  // background sweep). Always reading straight from widget.deliverable is
  // what makes those automatic updates actually reach the screen.

  bool _refreshingViews = false;

  Future<void> _refreshViews() async {
    if (_refreshingViews) return;
    setState(() => _refreshingViews = true);
    try {
      await ref.read(apiClientProvider).refreshDeliverableViews(widget.deliverable.id);
      widget.onRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Views updated')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _refreshingViews = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    final d = widget.deliverable;
    final c = widget.participation.campaign;

    final views     = d.viewCount;
    final reach     = d.reach;
    final likes     = d.likeCount;
    final comments  = d.commentCount;
    final shares    = d.shareCount;
    final estimated = d.estimatedPaise;
    final rate      = d.ratePer1kPaise;
    final rateDisplay = rate > 0
        ? '₹${(rate / 100).toStringAsFixed(2)} / 1K views'
        : null;

    final submittedAt = d.liveSubmittedAt != null
        ? DateFormat('MMM d, h:mm a').format(
            DateTime.parse(d.liveSubmittedAt!).toLocal())
        : null;

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // ── "Link submitted" banner ─────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: vc.money.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: vc.money.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: vc.money,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Link submitted successfully!',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: vc.money,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your reel is live and tracking. Earnings update in real time 🎉',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: vc.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Post preview card ───────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: vc.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: vc.border),
            ),
            child: Row(
              children: [
                // Cover image
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: c.coverImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: c.coverImageUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _PlaceholderBox(vc: vc),
                        )
                      : _PlaceholderBox(vc: vc),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LIVE chip + date
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: vc.money.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: vc.money,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'LIVE',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: vc.money,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (submittedAt != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Submitted on $submittedAt',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: vc.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      // View on platform button
                      if (d.livePostUrl != null)
                        InkWell(
                          onTap: () => launchUrl(
                            Uri.parse(d.livePostUrl!),
                            mode: LaunchMode.externalApplication,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _platformIcon(d.platform),
                              const SizedBox(width: 6),
                              Text(
                                'View on ${_platformName(d.platform)}',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Estimated earnings card ─────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: vc.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: vc.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      // The rate pill and refresh button need to stay fully
                      // visible/tappable — Spacer() only distributes leftover
                      // space, it doesn't shrink anything when the row's
                      // content is too wide to begin with, so without this
                      // the pill (a fairly long string, e.g. "₹100.00 / 1K
                      // views") pushed everything past the screen edge.
                      child: Text(
                        'Estimated earnings',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: vc.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.info_outline_rounded,
                        size: 15, color: vc.muted),
                    const Spacer(),
                    if (rateDisplay != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          rateDisplay,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _refreshingViews ? null : _refreshViews,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: vc.deepSurface,
                          shape: BoxShape.circle,
                        ),
                        child: _refreshingViews
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: vc.muted,
                                ),
                              )
                            : Icon(Icons.refresh_rounded,
                                size: 16, color: vc.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatPaise(estimated),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: vc.moneyBright,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Earnings update in real time based on views',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: vc.muted,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: vc.deepSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _StatColumn(
                        icon: Icons.visibility_outlined,
                        iconColor: vc.money,
                        label: 'Views',
                        value: _formatNum(views),
                        valueColor: vc.money,
                        vc: vc,
                      ),
                      _Divider(vc: vc),
                      _StatColumn(
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: vc.money,
                        label: 'Estimated earnings',
                        value: _formatPaise(estimated),
                        valueColor: vc.money,
                        vc: vc,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Performance summary ─────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: vc.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: vc.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Performance summary',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: vc.onSurface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.info_outline_rounded,
                        size: 15, color: vc.muted),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _EngagementTile(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Reach',
                      value: _formatNum(reach),
                      vc: vc,
                    ),
                    _EngagementTile(
                      icon: Icons.favorite_outline_rounded,
                      label: 'Likes',
                      value: _formatNum(likes),
                      vc: vc,
                    ),
                    _EngagementTile(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Comments',
                      value: _formatNum(comments),
                      vc: vc,
                    ),
                    _EngagementTile(
                      icon: Icons.send_outlined,
                      label: 'Shares',
                      value: _formatNum(shares),
                      vc: vc,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Important notes ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Important notes',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...[
                  'Earnings are calculated per 1,000 eligible views',
                  'Make sure your reel remains public',
                  'Do not delete or archive the reel until payout is completed',
                  'Payment is processed 30 days after the campaign closes',
                ].map(
                  (note) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_rounded,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: vc.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 12, color: vc.muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'All earnings are estimated and subject to platform verification.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11, color: vc.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _platformIcon(String platform) {
    if (platform == 'youtube') {
      return const Icon(Icons.play_circle_fill, color: Color(0xFFFF0000), size: 18);
    }
    if (platform == 'twitter' || platform == 'x') {
      return const Text('𝕏',
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black));
    }
    // Instagram gradient camera
    return ShaderMask(
      shaderCallback: (b) => const LinearGradient(
        colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(b),
      blendMode: BlendMode.srcIn,
      child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
    );
  }

  String _platformName(String p) {
    switch (p) {
      case 'youtube': return 'YouTube';
      case 'twitter':
      case 'x':      return 'X';
      default:        return 'Instagram';
    }
  }

  String _formatPaise(int paise) {
    final rupees = paise / 100.0;
    return '₹${NumberFormat('#,##,##0.00', 'en_IN').format(rupees)}';
  }

  String _formatNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(2)}K';
    return '$n';
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.vc,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;
  final HalchalColors vc;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 11, color: vc.muted),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.vc});
  final HalchalColors vc;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: vc.border);
}

class _EngagementTile extends StatelessWidget {
  const _EngagementTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.vc,
  });

  final IconData icon;
  final String label;
  final String value;
  final HalchalColors vc;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: primary),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: vc.muted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: vc.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderBox extends StatelessWidget {
  const _PlaceholderBox({required this.vc});
  final HalchalColors vc;

  @override
  Widget build(BuildContext context) => Container(
        width: 80,
        height: 80,
        color: vc.surface,
        child: Icon(Icons.image_outlined, color: vc.muted),
      );
}
