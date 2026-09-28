import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/primary_action_button.dart';
import '../../core/widgets/retry_error_view.dart';
import '../../core/widgets/vc_scaffold.dart';
import '../../theme/halchal_colors.dart';
import 'profile_providers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _avatarUrl;

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _initFrom(Map<String, dynamic> user) {
    if (_initialized) return;
    _nameController.text = user['displayName'] as String? ?? '';
    _bioController.text = user['bio'] as String? ?? '';
    _avatarUrl = user['avatarUrl'] as String?;
    _initialized = true;
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _pickAndUploadAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (file == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final ext = file.name.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final url = await ref.read(apiClientProvider).uploadAvatar(
            filePath: file.path,
            fileName: file.name,
            mimeType: mime,
          );
      setState(() => _avatarUrl = url);
      ref.invalidate(profileMeProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).updateProfile(
            displayName: _nameController.text.trim(),
            bio: _bioController.text.trim(),
          );
      // Awaited, not a fire-and-forget invalidate() — reported live: saving,
      // then quickly reopening Edit Profile, showed the pre-save bio again
      // (not the just-saved one) until a further refresh or round-trip.
      // invalidate() only marks the provider stale; it doesn't wait for the
      // refetch, so popping right after it could land back before the new
      // value had actually loaded — and if the next Edit Profile screen's
      // _initFrom happened to run against that still-stale cached value, its
      // one-time-init guard would lock the fields onto it, never picking up
      // the real value even once the refetch did resolve moments later.
      // Awaiting the refetch here means the cache is guaranteed fresh by the
      // time this screen pops, closing that whole race window.
      // Awaited for the refetch to complete — the value itself isn't
      // needed since ref.watch(profileMeProvider) elsewhere picks up the
      // now-fresh cache on its own.
      // ignore: unused_result
      await ref.refresh(profileMeProvider.future);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileMeProvider);
    final vc = HalchalColors.of(context);

    return VcScaffold(
      title: 'Edit Profile',
      showBack: true,
      body: me.when(
        // profileMeProvider watches the app-wide realtime tick (see
        // profile_providers.dart), which bumps on ANY realtime event
        // anywhere in the app — another creator's deliverable getting
        // reviewed, any brand publishing a campaign, etc., not just
        // something about this user. Riverpod treats that as a "reload"
        // (a watched dependency changed), not a "refresh" (invalidate) —
        // skipLoadingOnRefresh defaults to true and would've been fine,
        // but skipLoadingOnReload defaults to false, so without this the
        // whole form (including whatever's currently in the bio field)
        // got torn down to a bare spinner and rebuilt on literally any
        // unrelated realtime event elsewhere on the platform, dropping
        // the TextField's focus/keyboard mid-type. Reported live as "a
        // glitch when updating bio" — it's this, not anything bio-specific.
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetryErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(profileMeProvider),
        ),
        data: (user) {
          _initFrom(user);
          final primary = Theme.of(context).colorScheme.primary;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 172,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(32),
                      ),
                      child: SizedBox(
                        height: 108,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [vc.primaryVariant, primary],
                                ),
                              ),
                            ),
                            Positioned(
                              top: -60,
                              left: -40,
                              child: Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: -70,
                              right: -30,
                              child: Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 60,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: vc.background,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primary.withValues(alpha: 0.35),
                                    blurRadius: 24,
                                    spreadRadius: 1,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(0),
                              child: CircleAvatar(
                                radius: 44,
                                backgroundColor: primary.withValues(alpha: 0.15),
                                backgroundImage: _avatarUrl != null
                                    ? CachedNetworkImageProvider(_avatarUrl!)
                                    : null,
                                child: _avatarUrl == null
                                    ? Text(
                                        _initialsFor(_nameController.text.isEmpty
                                            ? 'Creator'
                                            : _nameController.text),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: primary,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            if (_uploadingAvatar)
                              const Positioned.fill(
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Colors.black45,
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onTap: _uploadingAvatar
                                    ? null
                                    : _pickAndUploadAvatar,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [primary, vc.primaryVariant],
                                    ),
                                    border: Border.all(
                                      color: vc.background,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primary.withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded,
                                      size: 15, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              _LabeledField(
                label: 'DISPLAY NAME',
                vc: vc,
                child: TextField(
                  controller: _nameController,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: vc.onSurface,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _LabeledField(
                label: 'PHONE',
                vc: vc,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (user['phone'] as String?)?.isNotEmpty == true
                            ? user['phone'] as String
                            : 'Not set',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: vc.onSurface,
                        ),
                      ),
                    ),
                    Icon(Icons.lock_outline_rounded, size: 14, color: vc.muted),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _LabeledField(
                label: 'BIO',
                vc: vc,
                child: TextField(
                  controller: _bioController,
                  maxLines: 4,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: vc.onSurface,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    filled: false,
                    hintText: 'Tell brands a bit about your content...',
                    hintStyle: GoogleFonts.inter(fontSize: 14, color: vc.muted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryActionButton(
                icon: Icons.check_rounded,
                label: _saving ? 'Saving...' : 'Save changes',
                loading: _saving,
                vc: vc,
                onPressed: _save,
              ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.vc,
    required this.child,
  });

  final String label;
  final HalchalColors vc;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: vc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vc.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: vc.muted,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
