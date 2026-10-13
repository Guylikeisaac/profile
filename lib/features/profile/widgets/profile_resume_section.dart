import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/repository_exception.dart';
import '../../../core/helpers/snackbar_helper.dart';
import '../../../core/router/route_names.dart';
import '../../resume/data/models/resume_file.dart';
import '../../resume/providers/profile_resume_provider.dart';
import '../../resume/providers/resume_upload_provider.dart';
import '../../resume/screens/resume_viewer_screen.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import 'profile_section.dart';
import 'profile_view_sections.dart' show ProfileChipFace, kProfileResumeNeon;
import 'profile_surface.dart';
import 'resume_manage_sheet.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../shared/widgets/app_button.dart';

/// Self-View "Resume" management card (below Social Links, above Bio), driven
/// by [profileResumeProvider] (`resume/user/{userId}/latest?uploadedOnly=true`):
///
///  • no uploaded file → dashed upload CTA into the existing
///    [RouteNames.resumeUpload] flow;
///  • file on record → file tile (name + honest metadata — the payload
///    carries no original filename or size, so both derive from the S3 key
///    and `createdAt`) with View (presigned URL) and Edit (replace/delete
///    sheet) actions.
class ProfileResumeCard extends ConsumerStatefulWidget {
  const ProfileResumeCard({super.key});

  @override
  ConsumerState<ProfileResumeCard> createState() => _ProfileResumeCardState();
}

class _ProfileResumeCardState extends ConsumerState<ProfileResumeCard> {
  /// The View tap fetches a presigned URL first — spinner on the pill, and a
  /// re-entrancy guard so a slow fetch can't stack viewers.
  bool _viewBusy = false;

  Future<void> _openUploadFlow() async {
    await context.push<bool>(RouteNames.resumeUpload);
    // The visit may have stored a new file (the upload screen already
    // refreshes the profile providers when parsing lands) — re-read ours.
    ref.invalidate(profileResumeProvider);
  }

  Future<void> _view(ResumeFile file) async {
    if (_viewBusy) return;
    setState(() => _viewBusy = true);
    try {
      final url = await ref
          .read(resumeRepositoryProvider)
          .resumeDownloadUrl(resumeKey: file.resumeKey);
      if (!mounted) return;
      final opened = await openResumeFile(
        context,
        url: url,
        fileName: file.fileName,
      );
      if (!opened && mounted) {
        showSnackbar(context, "Couldn't open your resume.", isError: true);
      }
    } catch (e) {
      if (mounted) {
        showSnackbar(
          context,
          e is RepositoryException
              ? e.message
              : "Couldn't open your resume. Please try again.",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _viewBusy = false);
    }
  }

  Future<void> _edit(ResumeFile file) async {
    // The sheet refreshes profileResumeProvider itself after a successful
    // replace/delete; the unconditional re-read below is a cheap safety net
    // for dismissal paths that raced an in-flight mutation.
    await openResumeManageSheet(context, file);
    if (mounted) ref.invalidate(profileResumeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final resumeAsync = ref.watch(profileResumeProvider);

    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.description_outlined,
            title: 'Resume',
          ),
          const SizedBox(height: 12),
          resumeAsync.when(
            loading: () => const _ResumeLoadingRow(),
            error: (_, __) => _ResumeErrorRow(
              onRetry: () => ref.invalidate(profileResumeProvider),
            ),
            data: (file) => file == null
                ? _ResumeEmptyZone(onTap: _openUploadFlow)
                : _ResumeFileBody(
                    file: file,
                    viewBusy: _viewBusy,
                    onView: () => _view(file),
                    onEdit: () => _edit(file),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight placeholder while the latest-resume read is in flight, sized
/// like the file tile so the card doesn't jump when it resolves.
class _ResumeLoadingRow extends StatelessWidget {
  const _ResumeLoadingRow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 56,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ResumeErrorRow extends StatelessWidget {
  const _ResumeErrorRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Row(
      children: [
        Expanded(
          child: Text(
            "Couldn't load your resume.",
            style: TextStyle(fontSize: 13, color: tokens.textTertiary),
          ),
        ),
        AppButton.text(label: 'Retry', onPressed: onRetry),
      ],
    );
  }
}

/// Empty state per the design frame: dashed zone, centered upload glyph,
/// "Choose new file" CTA and the format/size rule.
class _ResumeEmptyZone extends StatelessWidget {
  const _ResumeEmptyZone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    // The shared drop-zone treatment: dashed interactive edge, upload fill,
    // glyph and label in `controlInk`. Same as the Proof of Work add tile, so
    // every "put a file here" on the profile looks like the same kind of thing.
    return DottedBorder(
      borderType: BorderType.RRect,
      radius: const Radius.circular(ProfileSurfaceTokens.nestedRadius),
      color: tokens.uploadZoneBorder,
      strokeWidth: 1.4,
      dashPattern: const [4, 4],
      child: InkWell(
        borderRadius: BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: tokens.uploadZoneFill,
            borderRadius:
                BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
          ),
          child: Column(
            children: [
              Icon(Icons.upload_outlined, size: 26, color: tokens.controlInk),
              const SizedBox(height: 10),
              Text(
                'Choose new file',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.controlInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PDF, DOCX, or DOC · max 5 MB',
                style: TextStyle(
                  fontSize: 12.5,
                  color: tokens.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// File tile + View/Edit pill row (design frame's uploaded state).
class _ResumeFileBody extends StatelessWidget {
  const _ResumeFileBody({
    required this.file,
    required this.viewBusy,
    required this.onView,
    required this.onEdit,
  });

  final ResumeFile file;
  final bool viewBusy;
  final VoidCallback onView;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSurface(
          tier: ProfileSurfaceTier.raised,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const ProfileGlyphTile(
                icon: Icons.description_outlined,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    if (file.metaLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        file.metaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: tokens.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ResumeActionPill(
                icon: Icons.visibility_outlined,
                label: 'View',
                busy: viewBusy,
                onTap: onView,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ResumeActionPill(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onTap: onEdit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The View / Edit pair: the app's secondary button at its compact size —
/// the same control, loading state included, as every other secondary action.
class _ResumeActionPill extends StatelessWidget {
  const _ResumeActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppButton.secondary(
      label: label,
      leading: icon,
      onPressed: onTap,
      loading: busy,
      size: AppButtonSize.compact,
    );
  }
}

/// The owner's resume as a chip in the Social Links grid: opens the file on
/// record, or the upload flow when there is none yet.
class ProfileResumeChip extends ConsumerStatefulWidget {
  const ProfileResumeChip({super.key});

  @override
  ConsumerState<ProfileResumeChip> createState() => _ProfileResumeChipState();
}

class _ProfileResumeChipState extends ConsumerState<ProfileResumeChip> {
  bool _busy = false;

  Future<void> _open(ResumeFile? file) async {
    if (_busy) return;
    if (file == null) {
      await context.push<bool>(RouteNames.resumeUpload);
      ref.invalidate(profileResumeProvider);
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await ref
          .read(resumeRepositoryProvider)
          .resumeDownloadUrl(resumeKey: file.resumeKey);
      if (!mounted) return;
      final opened =
          await openResumeFile(context, url: url, fileName: file.fileName);
      if (!opened && mounted) {
        showSnackbar(context, "Couldn't open your resume.", isError: true);
      }
    } catch (e) {
      if (mounted) {
        showSnackbar(
          context,
          e is RepositoryException
              ? e.message
              : "Couldn't open your resume. Please try again.",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = ref.watch(profileResumeProvider).value;
    final ink = context.colorScheme.onSurface;
    return ProfileChipFace(
      glyph: Icon(
        file == null ? Icons.upload_file_outlined : Icons.description_outlined,
        size: 14,
        color: ink,
      ),
      glyphTile: ink.withValues(alpha: 0.10),
      neonLabel: kProfileResumeNeon,
      label: file == null ? 'Add resume' : 'Resume',
      semanticLabel: file == null ? 'Upload your resume' : 'Open your resume',
      busy: _busy,
      expand: true,
      onTap: () => _open(file),
    );
  }
}
