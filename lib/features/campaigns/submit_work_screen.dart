import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/realtime/campaign_realtime_scope.dart';
import '../../core/campaign/platform_labels.dart';
import 'campaign_providers.dart';
import '../../core/participation/rejection_history.dart';
import '../../core/layout/app_spacing.dart';
import '../../core/validation/drive_url.dart';
import '../../core/widgets/retry_error_view.dart';
import '../../core/widgets/vc_scaffold.dart';
import '../../theme/halchal_colors.dart';
import '../marketplace/marketplace_providers.dart';
import '../marketplace/widgets/marketplace_video_tile.dart';

enum _SubmitMethod { drive, device, marketplace }

class SubmitWorkScreen extends ConsumerStatefulWidget {
  const SubmitWorkScreen({super.key, required this.campaignId});

  final String campaignId;

  @override
  ConsumerState<SubmitWorkScreen> createState() => _SubmitWorkScreenState();
}

class _SubmitWorkScreenState extends ConsumerState<SubmitWorkScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _driveControllers = <String, TextEditingController>{};
  final _expandedHistory = <String>{};
  final _uploadedUrls = <String, String>{};
  final _uploadingIds = <String>{};
  final _marketplaceOptIn = <String>{};
  final _repostingIds = <String>{};
  bool _loading = false;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _driveControllers.values) {
      c.dispose();
    }
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    ref.invalidate(participationSubmitProvider(widget.campaignId));
    ref.invalidate(campaignParticipationProvider(widget.campaignId));
    await ref.read(participationSubmitProvider(widget.campaignId).future);
  }

  TextEditingController _controllerFor(String id, String? initial) =>
      _driveControllers.putIfAbsent(
        id,
        () => TextEditingController(text: initial ?? ''),
      );

  String _effectiveUrl(FormatDeliverable d) =>
      _uploadedUrls[d.id] ?? _driveControllers[d.id]?.text.trim() ?? '';

  bool _canSubmitAll(Participation p) {
    for (final d in p.deliverables) {
      if (!d.isRejected && !d.isDraftPending) continue;
      final url = _effectiveUrl(d);
      if (url.isEmpty) return false;
      final isDrive = url.startsWith('https://drive.google.com') ||
          url.startsWith('https://docs.google.com');
      if (isDrive && driveUrlError(url) != null) return false;
      if (d.isRejected && isDrive && isSameRejectedDriveUrl(d, url)) {
        return false;
      }
    }
    return p.deliverables.any((d) => d.isRejected || d.isDraftPending);
  }

  Future<void> _submitDrafts(Participation p) async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      for (final d in p.deliverables) {
        if (!d.isRejected && !d.isDraftPending) continue;
        final url = _effectiveUrl(d);
        if (url.isEmpty) continue;
        if (d.isRejected && isSameRejectedDriveUrl(d, url)) {
          _showSnack('${formatPlatformLabel(d.platform)}: use a new link — the previous one was rejected.');
          return;
        }
        await api.submitDeliverableDraft(
          deliverableId: d.id,
          draftDriveUrl: url,
          listedInMarketplace: _marketplaceOptIn.contains(d.id),
        );
      }
      ref.invalidate(participationSubmitProvider(widget.campaignId));
      ref.invalidate(campaignParticipationProvider(widget.campaignId));
      if (!mounted) return;
      _showSnack('Submitted for review!');
      context.go('/participations/${p.id}');
    } on ApiException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _repost(Participation p, String sourceDeliverableId) async {
    final creatorProfileId = p.creatorProfile?.id;
    if (creatorProfileId == null) return;
    setState(() => _repostingIds.add(sourceDeliverableId));
    try {
      await ref
          .read(apiClientProvider)
          .repostMarketplaceListing(sourceDeliverableId, creatorProfileId);
      ref.invalidate(participationSubmitProvider(widget.campaignId));
      ref.invalidate(campaignParticipationProvider(widget.campaignId));
      if (!mounted) return;
      _showSnack('Reposted — pending review');
      context.go('/participations/${p.id}');
    } on ApiException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _repostingIds.remove(sourceDeliverableId));
    }
  }

  static const _videoExtensions = {'mp4', 'mov', 'm4v', 'avi', 'mkv'};
  // Matches the backend's actual enforced limits (creator-participation
  // .controller.ts's upload-draft route, fileSize: 500 * 1024 * 1024 for
  // video / the UI's own stated "20MB" for images) — checked here so an
  // oversized file is rejected immediately instead of only after
  // uploading the whole thing. Reported live: a ~976MB file spent 26+
  // seconds uploading before the backend's 413 came back, and that 413
  // isn't shaped like an ApiException, so it fell through to a generic
  // "Upload failed. Please try again." with no indication of why.
  static const _maxVideoBytes = 500 * 1024 * 1024;
  static const _maxImageBytes = 20 * 1024 * 1024;

  Future<void> _pickAndUpload(FormatDeliverable d) async {
    final picker = ImagePicker();
    final file = await picker.pickMedia();
    if (file == null) return;

    final ext = file.name.split('.').last.toLowerCase();
    final isVideo = _videoExtensions.contains(ext);
    final maxBytes = isVideo ? _maxVideoBytes : _maxImageBytes;
    final sizeBytes = await file.length();
    if (sizeBytes > maxBytes) {
      final maxMb = maxBytes ~/ (1024 * 1024);
      final actualMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(0);
      _showSnack(
        '${isVideo ? "Video" : "Image"} is ${actualMb}MB — max is ${maxMb}MB.',
      );
      return;
    }

    setState(() => _uploadingIds.add(d.id));
    try {
      final api = ref.read(apiClientProvider);
      final mime = isVideo
          ? (ext == 'mov' ? 'video/quicktime' : 'video/mp4')
          : (ext == 'png' ? 'image/png' : 'image/jpeg');
      final url = await api.uploadDraftFile(
        deliverableId: d.id,
        filePath: file.path,
        fileName: file.name,
        mimeType: mime,
      );
      setState(() => _uploadedUrls[d.id] = url);
      _showSnack('File uploaded successfully');
    } on ApiException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingIds.remove(d.id));
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final participation = ref.watch(participationSubmitProvider(widget.campaignId));
    final vc = HalchalColors.of(context);

    return participation.when(
      // participationSubmitProvider watches the app-wide realtime tick
      // (see campaign_providers.dart), which bumps on ANY realtime event
      // anywhere on the platform, unrelated to this submission. Riverpod
      // treats that as a "reload" (skipLoadingOnReload defaults to
      // false), so without this the loading branch below — a
      // completely different VcScaffold subtree — replaced the whole
      // screen on any such event, destroying _DeliverableSubmitCard's
      // local _method state (which method — device upload vs. Drive
      // link — is currently selected). Reported live: picking a file to
      // upload from device, then having the screen revert to "Submit
      // Google Drive link" selected once the upload finished, even
      // though the file *had* uploaded successfully (that part lives in
      // the parent's state, which survives — only the child's selected-
      // method toggle was being lost).
      skipLoadingOnReload: true,
      loading: () => const VcScaffold(
        title: 'Submit your work',
        showBack: true,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => VcScaffold(
        title: 'Submit your work',
        showBack: true,
        body: RetryErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(participationSubmitProvider(widget.campaignId)),
        ),
      ),
      data: (p) {
        for (final d in p.deliverables) {
          _controllerFor(d.id, d.draftDriveUrl);
        }

        final pendingDeliverables =
            p.deliverables.where((d) => d.isRejected || d.isDraftPending).toList();
        final otherDeliverables =
            p.deliverables.where((d) => !d.isRejected && !d.isDraftPending).toList();

        return CampaignRealtimeScope(
          campaignId: widget.campaignId,
          child: Scaffold(
            backgroundColor: vc.background,
            appBar: AppBar(
              backgroundColor: vc.background,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/submissions'),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Submit your work',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 17, fontWeight: FontWeight.w800, color: vc.onSurface)),
                  Text(p.campaign.displayBrand,
                      style: GoogleFonts.inter(fontSize: 12, color: vc.muted)),
                ],
              ),
            ),
            body: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, AppSpacing.floatingNavBottom(context) + 80),
                children: [
                  if (pendingDeliverables.isNotEmpty) ...[
                    ...pendingDeliverables.asMap().entries.map((e) {
                      final d = e.value;
                      final anim = CurvedAnimation(
                        parent: _entrance,
                        curve: Interval(
                          (e.key * 0.1).clamp(0.0, 0.7),
                          ((e.key * 0.1) + 0.4).clamp(0.0, 1.0),
                          curve: Curves.easeOutCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: anim,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _DeliverableSubmitCard(
                            deliverable: d,
                            driveController: _controllerFor(d.id, d.draftDriveUrl),
                            uploadedUrl: _uploadedUrls[d.id],
                            isUploading: _uploadingIds.contains(d.id),
                            expandedHistory: _expandedHistory,
                            onExpandHistory: (id) => setState(() {
                              _expandedHistory.contains(id)
                                  ? _expandedHistory.remove(id)
                                  : _expandedHistory.add(id);
                            }),
                            onPickFile: () => _pickAndUpload(d),
                            onRemoveUpload: () => setState(() => _uploadedUrls.remove(d.id)),
                            onChanged: () => setState(() {}),
                            listedInMarketplace: _marketplaceOptIn.contains(d.id),
                            onToggleMarketplace: (value) => setState(() {
                              if (value) {
                                _marketplaceOptIn.add(d.id);
                              } else {
                                _marketplaceOptIn.remove(d.id);
                              }
                            }),
                            campaignId: p.campaignId,
                            creatorProfileId: p.creatorProfile?.id,
                            repostingIds: _repostingIds,
                            onRepost: (sourceId) => _repost(p, sourceId),
                            vc: vc,
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    _SubmissionTipsCard(vc: vc),
                    const SizedBox(height: 12),
                    _WhatHappensNextCard(vc: vc),
                  ],
                  if (otherDeliverables.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionHeader(context, vc, 'Other formats', null),
                    const SizedBox(height: 8),
                    ...otherDeliverables.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _CompletedDeliverableRow(d: d, vc: vc),
                        )),
                  ],
                ],
              ),
            ),
            bottomNavigationBar: pendingDeliverables.isEmpty
                ? null
                : SafeArea(
                    child: Padding(
                      padding: AppSpacing.bottomActionPadding(context),
                      child: _PrimaryActionButton(
                        icon: p.deliverables.any((d) => d.isRejected)
                            ? Icons.refresh_rounded
                            : Icons.send_rounded,
                        label: _loading
                            ? 'Submitting...'
                            : p.deliverables.any((d) => d.isRejected)
                                ? 'Resubmit for review'
                                : 'Submit for review',
                        loading: _loading,
                        vc: vc,
                        onPressed:
                            _canSubmitAll(p) ? () => _submitDrafts(p) : null,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(
      BuildContext context, HalchalColors vc, String title, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 13, color: vc.muted)),
        ],
      ],
    );
  }
}

class _DeliverableSubmitCard extends StatefulWidget {
  const _DeliverableSubmitCard({
    required this.deliverable,
    required this.driveController,
    required this.uploadedUrl,
    required this.isUploading,
    required this.expandedHistory,
    required this.onExpandHistory,
    required this.onPickFile,
    required this.onRemoveUpload,
    required this.onChanged,
    required this.listedInMarketplace,
    required this.onToggleMarketplace,
    required this.campaignId,
    required this.creatorProfileId,
    required this.repostingIds,
    required this.onRepost,
    required this.vc,
  });

  final FormatDeliverable deliverable;
  final TextEditingController driveController;
  final String? uploadedUrl;
  final bool isUploading;
  final Set<String> expandedHistory;
  final void Function(String id) onExpandHistory;
  final VoidCallback onPickFile;
  final VoidCallback onRemoveUpload;
  final VoidCallback onChanged;
  final bool listedInMarketplace;
  final ValueChanged<bool> onToggleMarketplace;
  final String campaignId;
  final String? creatorProfileId;
  final Set<String> repostingIds;
  final ValueChanged<String> onRepost;
  final HalchalColors vc;

  @override
  State<_DeliverableSubmitCard> createState() => _DeliverableSubmitCardState();
}

class _DeliverableSubmitCardState extends State<_DeliverableSubmitCard> {
  _SubmitMethod _method = _SubmitMethod.drive;

  FormatDeliverable get d => widget.deliverable;
  HalchalColors get vc => widget.vc;

  @override
  Widget build(BuildContext context) {
    final draftUrl = widget.driveController.text.trim();
    final draftUrlError =
        draftUrl.isEmpty ? null : driveUrlError(draftUrl);
    final statusVisual = _statusVisual(d.status, vc);
    final heroCopy = _heroCopy(d);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_platformIcon(d.platform), size: 14, color: vc.muted),
            const SizedBox(width: 6),
            Text(
              formatPlatformLabel(d.platform).toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: vc.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        _HeroBanner(
          icon: statusVisual.icon,
          color: statusVisual.color,
          tag: statusVisual.label,
          headline: heroCopy.headline,
          message: heroCopy.message,
          illustration: d.isRejected
              ? Icons.description_rounded
              : Icons.cloud_upload_rounded,
          vc: vc,
        ),

        if (priorRejectionEvents(d).isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => widget.onExpandHistory(d.id),
            child: Row(children: [
              Icon(
                widget.expandedHistory.contains(d.id)
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 18,
                color: vc.muted,
              ),
              Text('Previous feedback (${priorRejectionEvents(d).length})',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: vc.muted)),
            ]),
          ),
          if (widget.expandedHistory.contains(d.id))
            ...priorRejectionEvents(d).map((e) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: vc.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: vc.border),
                    ),
                    child: Text(e.rejectionReason, style: const TextStyle(fontSize: 13)),
                  ),
                )),
        ],

        const SizedBox(height: 16),

        // Section label
        Text('Submit your content',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w800, color: vc.onSurface)),
        const SizedBox(height: 4),
        Text('Choose any one of the options below',
            style: TextStyle(fontSize: 12, color: vc.muted)),
        const SizedBox(height: 12),

        // Upload from device option (first)
        _MethodCard(
          selected: _method == _SubmitMethod.device,
          onTap: () => setState(() => _method = _SubmitMethod.device),
          vc: vc,
          icon: Icon(Icons.cloud_upload_outlined, color: vc.primary, size: 24),
          title: 'Upload from device',
          subtitle: 'Upload your content directly',
          child: _method == _SubmitMethod.device
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      widget.uploadedUrl != null
                          ? _UploadedFileRow(
                              url: widget.uploadedUrl!,
                              vc: vc,
                              onRemove: widget.onRemoveUpload,
                            )
                          : _DropZone(
                              isUploading: widget.isUploading,
                              vc: vc,
                              onTap: widget.onPickFile,
                            ),
                      if (kClipMarketplaceEnabled) ...[
                        const SizedBox(height: 12),
                        _MarketplaceOptInRow(
                          value: widget.listedInMarketplace,
                          onChanged: widget.onToggleMarketplace,
                          vc: vc,
                        ),
                      ],
                    ],
                  ),
                )
              : null,
        ),

        const SizedBox(height: 10),

        // Drive link option (second)
        _MethodCard(
          selected: _method == _SubmitMethod.drive,
          onTap: () => setState(() => _method = _SubmitMethod.drive),
          vc: vc,
          icon: const _DriveLogo(size: 24),
          title: 'Submit Google Drive link',
          subtitle: 'Paste a public Google Drive link to your content',
          child: _method == _SubmitMethod.drive
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: widget.driveController,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Paste your Google Drive link here',
                                hintStyle:
                                    TextStyle(color: vc.muted, fontSize: 13),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                errorText: draftUrlError,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: vc.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: vc.border),
                                ),
                              ),
                              onChanged: (_) => widget.onChanged(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              final data =
                                  await Clipboard.getData('text/plain');
                              if (data?.text != null) {
                                widget.driveController.text = data!.text!;
                                widget.onChanged();
                              }
                            },
                            child: Text('Paste',
                                style: TextStyle(
                                    color: vc.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.lock_outline,
                              size: 13, color: vc.muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Make sure the link is viewable by anyone with the link',
                              style:
                                  TextStyle(fontSize: 11, color: vc.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : null,
        ),

        const SizedBox(height: 10),

        // Reuse an already-approved clip from the marketplace (third) —
        // hidden until we have Instagram's permissions for reposting.
        if (kClipMarketplaceEnabled && widget.creatorProfileId != null)
          _MethodCard(
            selected: _method == _SubmitMethod.marketplace,
            onTap: () => setState(() => _method = _SubmitMethod.marketplace),
            vc: vc,
            icon: Icon(Icons.storefront_outlined, color: vc.money, size: 24),
            title: 'Reuse from Marketplace',
            subtitle: 'Repost another clipper\'s approved clip and split earnings',
            child: _method == _SubmitMethod.marketplace
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _MarketplaceReuseSection(
                      campaignId: widget.campaignId,
                      creatorProfileId: widget.creatorProfileId!,
                      platform: d.platform,
                      repostingIds: widget.repostingIds,
                      onRepost: widget.onRepost,
                      vc: vc,
                    ),
                  )
                : null,
          ),
      ],
    );
  }
}

class _MarketplaceReuseSection extends ConsumerWidget {
  const _MarketplaceReuseSection({
    required this.campaignId,
    required this.creatorProfileId,
    required this.platform,
    required this.repostingIds,
    required this.onRepost,
    required this.vc,
  });

  final String campaignId;
  final String creatorProfileId;
  final String platform;
  final Set<String> repostingIds;
  final ValueChanged<String> onRepost;
  final HalchalColors vc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(
      marketplaceListingsProvider((campaignId, creatorProfileId)),
    );

    return listings.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Row(
        children: [
          Expanded(
            child: Text('$e', style: TextStyle(fontSize: 12, color: vc.muted)),
          ),
          TextButton(
            onPressed: () => ref.invalidate(
              marketplaceListingsProvider((campaignId, creatorProfileId)),
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
      data: (items) {
        final matching = items.where((l) => l.platform == platform).toList();
        if (matching.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No approved clips are available to repost for this format yet.',
              style: TextStyle(fontSize: 12.5, color: vc.muted),
            ),
          );
        }
        final preview = matching.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                for (var i = 0; i < preview.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: MarketplaceVideoTile(
                      listing: preview[i],
                      busy: repostingIds.contains(preview[i].sourceDeliverableId),
                      onRepost: () => onRepost(preview[i].sourceDeliverableId),
                      vc: vc,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => context.push(
                Uri(
                  path: '/campaigns/$campaignId/marketplace',
                  queryParameters: {'creatorProfileId': creatorProfileId},
                ).toString(),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: vc.primary,
                side: BorderSide(color: vc.primary.withValues(alpha: 0.4)),
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Show all'),
            ),
          ],
        );
      },
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.selected,
    required this.onTap,
    required this.vc,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final HalchalColors vc;
  final Widget icon;
  final String title;
  final String subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? vc.primary.withValues(alpha: 0.06) : vc.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? vc.primary : vc.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: vc.background,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: vc.border),
                  ),
                  alignment: Alignment.center,
                  child: icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(fontSize: 12, color: vc.muted)),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected ? vc.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: selected
                        ? null
                        : Border.all(color: vc.border, width: 1.5),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.isUploading,
    required this.vc,
    required this.onTap,
  });

  final bool isUploading;
  final HalchalColors vc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isUploading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: vc.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: vc.primary.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: isUploading
            ? Column(children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: vc.primary),
                ),
                const SizedBox(height: 10),
                Text('Uploading…',
                    style: TextStyle(fontSize: 13, color: vc.primary)),
              ])
            : Column(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: vc.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.cloud_upload_rounded, size: 24, color: vc.primary),
                ),
                const SizedBox(height: 10),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Tap to upload',
                        style: TextStyle(
                            color: vc.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                      TextSpan(
                        text: ' or drag & drop',
                        style: TextStyle(
                            color: vc.onSurface, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Videos up to 500MB (max 5 min) or images up to 20MB',
                  style: TextStyle(fontSize: 11, color: vc.muted),
                ),
              ]),
      ),
    );
  }
}

class _UploadedFileRow extends StatelessWidget {
  const _UploadedFileRow(
      {required this.url, required this.vc, required this.onRemove});

  final String url;
  final HalchalColors vc;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final filename = url.split('/').last.split('?').first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: vc.money.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vc.money.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: vc.money, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filename,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text('Uploaded', style: TextStyle(fontSize: 11, color: vc.muted)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 18, color: vc.muted),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceOptInRow extends StatelessWidget {
  const _MarketplaceOptInRow({
    required this.value,
    required this.onChanged,
    required this.vc,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final HalchalColors vc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: vc.money.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vc.money.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, size: 16, color: vc.money),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'List in the Marketplace',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: vc.onSurface,
                  ),
                ),
              ),
              Switch(
                value: value,
                activeThumbColor: vc.money,
                onChanged: onChanged,
              ),
            ],
          ),
          Text(
            'Once approved, other clippers can repost this clip and split '
            'earnings with you.',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: vc.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmissionTipsCard extends StatelessWidget {
  const _SubmissionTipsCard({required this.vc});

  final HalchalColors vc;

  static const _tips = [
    'Make sure your content is public and accessible',
    'Follow all the content rules mentioned in the brief',
    'Do not delete your post until the review is complete',
    'You will be notified once your submission is reviewed',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: vc.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vc.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: vc.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lightbulb_outline, color: vc.primary, size: 14),
              ),
              const SizedBox(width: 8),
              Text('Submission tips',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700, color: vc.primary)),
            ],
          ),
          const SizedBox(height: 10),
          ..._tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: vc.primary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(tip,
                        style: GoogleFonts.inter(fontSize: 12.5, color: vc.onSurface)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedDeliverableRow extends StatelessWidget {
  const _CompletedDeliverableRow({required this.d, required this.vc});

  final FormatDeliverable d;
  final HalchalColors vc;

  @override
  Widget build(BuildContext context) {
    final statusVisual = _statusVisual(d.status, vc);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: vc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vc.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: vc.background,
              shape: BoxShape.circle,
              border: Border.all(color: vc.border),
            ),
            child: Icon(_platformIcon(d.platform), color: vc.onSurface, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              formatPlatformLabel(d.platform),
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          _StatusTag(
            icon: statusVisual.icon,
            color: statusVisual.color,
            label: statusVisual.label,
          ),
          if (d.draftDriveUrl != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => launchUrl(
                Uri.parse(d.draftDriveUrl!),
                mode: LaunchMode.externalApplication,
              ),
              icon: Icon(Icons.open_in_new_rounded, size: 16, color: vc.primary),
              style: IconButton.styleFrom(
                backgroundColor: vc.primary.withValues(alpha: 0.10),
                padding: const EdgeInsets.all(6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Renders the official multi-tone Google Drive triangle logo from its
/// real SVG path data (source: gilbarbara/logos), so it's brand-accurate
/// rather than a hand-drawn approximation.
class _DriveLogo extends StatelessWidget {
  const _DriveLogo({this.size = 24});

  final double size;

  static const _facets = [
    (
      'M19.3542312,196.033928 L30.644172,215.534816 C32.9900287,219.64014 36.3622164,222.86588 40.3210929,225.211737 C51.6602421,210.818376 59.5534225,199.772864 64.000634,192.075201 C68.5137119,184.263529 74.0609657,172.045039 80.6423954,155.41973 C62.9064315,153.085282 49.4659974,151.918058 40.3210929,151.918058 C31.545465,151.918058 18.1051007,153.085282 0,155.41973 C0,159.964996 1.17298825,164.510261 3.51893479,168.615586 L19.3542312,196.033928 Z',
      Color(0xFF0066DA),
    ),
    (
      'M215.681443,225.211737 C219.64032,222.86588 223.012507,219.64014 225.358364,215.534816 L230.050377,207.470615 L252.483511,168.615586 C254.829368,164.510261 256.002446,159.964996 256.002446,155.41973 C237.79254,153.085282 224.376613,151.918058 215.754667,151.918058 C206.488712,151.918058 193.072785,153.085282 175.506888,155.41973 C182.010479,172.136093 187.484394,184.354584 191.928633,192.075201 C196.412073,199.863919 204.329677,210.909431 215.681443,225.211737 Z',
      Color(0xFFEA4335),
    ),
    (
      'M128.001268,73.3111515 C141.121182,57.4655263 150.162898,45.2470011 155.126415,36.6555757 C159.123121,29.7376196 163.521739,18.6920726 168.322271,3.51893479 C164.363395,1.1729583 159.818129,0 155.126415,0 L100.876121,0 C96.1841079,0 91.638842,1.31958557 87.6799655,3.51893479 C93.7861943,20.9210065 98.9675428,33.3058067 103.224011,40.6733354 C107.927832,48.8151881 116.186918,59.6944602 128.001268,73.3111515 Z',
      Color(0xFF00832D),
    ),
    (
      'M175.360141,155.41973 L80.6420959,155.41973 L40.3210929,225.211737 C44.2799694,227.557893 48.8252352,228.730672 53.5172481,228.730672 L202.485288,228.730672 C207.177301,228.730672 211.722567,227.411146 215.681443,225.211737 L175.360141,155.41973 Z',
      Color(0xFF2684FC),
    ),
    (
      'M128.001268,73.3111515 L87.680265,3.51893479 C83.7213885,5.86488134 80.3489013,9.09044179 78.0030446,13.1960654 L3.51893479,142.223575 C1.17298825,146.329198 0,150.874464 0,155.41973 L80.6423954,155.41973 L128.001268,73.3111515 Z',
      Color(0xFF00AC47),
    ),
    (
      'M215.241501,77.7099697 L177.999492,13.1960654 C175.653635,9.09044179 172.281148,5.86488134 168.322271,3.51893479 L128.001268,73.3111515 L175.360141,155.41973 L255.855999,155.41973 C255.855999,150.874464 254.682921,146.329198 252.337064,142.223575 L215.241501,77.7099697 Z',
      Color(0xFFFFBA00),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DriveLogoPainter(_facets)),
    );
  }
}

class _DriveLogoPainter extends CustomPainter {
  _DriveLogoPainter(this.facets);

  final List<(String, Color)> facets;

  static const _viewWidth = 256.0;
  static const _viewHeight = 228.730672;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewWidth;
    final dx = (size.width - _viewWidth * scale) / 2;
    final dy = (size.height - _viewHeight * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    for (final (d, color) in facets) {
      canvas.drawPath(_parseSvgPath(d), Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Minimal parser for the subset of SVG path commands (M/L/C/Z, absolute
/// coordinates only) used by the Drive logo paths above.
Path _parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLCZ]|-?\d*\.?\d+(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        path.moveTo(next(), next());
      case 'L':
        path.lineTo(next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
      case 'Z':
        path.close();
    }
  }
  return path;
}

IconData _platformIcon(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('instagram')) return Icons.camera_alt_rounded;
  if (p.contains('youtube')) return Icons.smart_display_rounded;
  if (p.contains('twitter') || p.contains('_x') || p == 'x') {
    return Icons.alternate_email_rounded;
  }
  return Icons.videocam_rounded;
}

({String headline, String message}) _heroCopy(FormatDeliverable d) {
  if (d.isRejected) {
    return (
      headline: 'Changes requested',
      message: d.latestRejectionReason ??
          'Update your draft with the requested changes and resubmit.',
    );
  }
  return (
    headline: 'Ready for your draft',
    message: 'Choose how you\'d like to share your content below.',
  );
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.icon,
    required this.color,
    required this.tag,
    required this.headline,
    required this.message,
    required this.illustration,
    required this.vc,
  });

  final IconData icon;
  final Color color;
  final String tag;
  final String headline;
  final String message;
  final IconData illustration;
  final HalchalColors vc;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(vc.surface, color, 0.40)!,
              Color.lerp(vc.surface, color, 0.08)!,
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -16,
              bottom: -20,
              child: Icon(illustration, size: 108, color: color.withValues(alpha: 0.14)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, color: Colors.white, size: 19),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tag.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headline,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: vc.onSurface,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: vc.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({IconData icon, Color color, String label}) _statusVisual(
  String status,
  HalchalColors vc,
) {
  switch (status) {
    case 'draft_pending':
      return (icon: Icons.upload_file_rounded, color: vc.primary, label: 'Pending');
    case 'under_review':
      return (
        icon: Icons.hourglass_top_rounded,
        color: vc.warning,
        label: 'In Review',
      );
    case 'draft_rejected':
      return (
        icon: Icons.report_problem_rounded,
        color: vc.error,
        label: 'Changes Needed',
      );
    case 'draft_approved':
      return (
        icon: Icons.check_circle_rounded,
        color: vc.money,
        label: 'Approved',
      );
    case 'live_submitted':
    case 'proof_under_review':
      return (
        icon: Icons.hourglass_top_rounded,
        color: vc.warning,
        label: 'In Review',
      );
    case 'proof_approved':
      return (
        icon: Icons.check_circle_rounded,
        color: vc.money,
        label: 'Proof Approved',
      );
    case 'proof_rejected':
      return (
        icon: Icons.report_problem_rounded,
        color: vc.error,
        label: 'Rejected',
      );
    default:
      return (
        icon: Icons.info_outline_rounded,
        color: vc.muted,
        label: status.replaceAll('_', ' '),
      );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.vc,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final HalchalColors vc;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [vc.primary, vc.primaryVariant],
        ),
        boxShadow: [
          BoxShadow(
            color: vc.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(icon, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WhatHappensNextCard extends StatelessWidget {
  const _WhatHappensNextCard({required this.vc});

  final HalchalColors vc;

  static const _steps = [
    (icon: Icons.upload_file_rounded, label: 'Your draft is submitted for review'),
    (
      icon: Icons.hourglass_top_rounded,
      label: 'The brand reviews it — usually within 1-2 days',
    ),
    (
      icon: Icons.notifications_active_rounded,
      label: "You'll be notified the moment they respond",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: vc.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.timeline_rounded, size: 14, color: vc.primary),
              ),
              const SizedBox(width: 8),
              Text(
                'What happens next',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: vc.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final step in _steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: vc.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: vc.border),
                    ),
                    child: Icon(step.icon, size: 12, color: vc.muted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        step.label,
                        style: GoogleFonts.inter(fontSize: 12.5, color: vc.onSurface),
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
