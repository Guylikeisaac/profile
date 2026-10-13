import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_exception.dart';
import '../../../core/helpers/snackbar_helper.dart';
import '../../profile_menu/providers/profile_menu_provider.dart';
import '../../resume/data/models/resume_file.dart';
import '../../resume/providers/profile_resume_provider.dart';
import '../../resume/providers/resume_upload_provider.dart';
import '../providers/profile_provider.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/confirm_action_dialog.dart';
import 'profile_sheet_kit.dart';
import 'profile_surface.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/theme_context_ext.dart';

/// Opens the Edit Resume sheet for the profile Resume card: replace the
/// current file (`resume/upload?update=true` + honest parse poll) or delete it
/// (`DELETE /resume/{id}`, confirmed first). Resolves `true` when something
/// changed — the sheet already refreshed [profileResumeProvider] itself.
Future<bool?> openResumeManageSheet(BuildContext context, ResumeFile resume) {
  return showProfileSheet<bool>(
    context,
    fullHeight: true,
    builder: (_) => _ResumeManageSheet(resume: resume),
  );
}

/// "Edit Resume" per the design frame: read-only name row, dashed
/// replace-file picker, Delete Resume + Update Resume footer. The
/// upload/parse machinery is [resumeUploadProvider] — the same notifier the
/// onboarding upload screen uses, here driven with `update: true`.
///
/// No "set as default resume" control: the design frame shows one, but no
/// backend endpoint for it exists (checked 2026-07-16) — deliberately omitted
/// rather than shipped as fake state.
class _ResumeManageSheet extends ConsumerStatefulWidget {
  const _ResumeManageSheet({required this.resume});

  final ResumeFile resume;

  @override
  ConsumerState<_ResumeManageSheet> createState() => _ResumeManageSheetState();
}

class _ResumeManageSheetState extends ConsumerState<_ResumeManageSheet> {
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    // The upload notifier is shared with the onboarding screen — start from a
    // clean slate so no stale picked file leaks in. Microtask: provider
    // writes are illegal during the first build.
    Future.microtask(() {
      if (mounted) ref.read(resumeUploadProvider.notifier).reset();
    });
  }

  void _update() {
    ref.read(resumeUploadProvider.notifier).upload(update: true);
  }

  Future<void> _confirmDelete() async {
    // The app's one confirmation dialog: keeping the resume is the filled,
    // safe action; the destructive one names what it removes.
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Delete resume?',
      // Mirrors the backend rule: the record always goes; the file is kept
      // server-side only while past job applications still reference it.
      message: 'This removes the uploaded resume from your profile. Copies '
          'already attached to past job applications are kept with those '
          'applications.',
      confirmLabel: 'Delete resume',
      cancelLabel: 'Keep resume',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(resumeRepositoryProvider).deleteResume(widget.resume.id);
      if (!mounted) return;
      // The card re-reads the (now empty) backend state and shows its upload
      // CTA again.
      ref.invalidate(profileResumeProvider);
      showSnackbar(context, 'Resume deleted');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showSnackbar(
        context,
        e is RepositoryException
            ? e.message
            : "Couldn't delete your resume. Please try again.",
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(resumeUploadProvider);
    final notifier = ref.read(resumeUploadProvider.notifier);

    ref.listen<ResumeUploadState>(resumeUploadProvider, (prev, next) {
      if (next.status == ResumeUploadStatus.success) {
        // New file on record → the card must re-read the backend state.
        ref.invalidate(profileResumeProvider);
        if (next.parsed) {
          // Parsing confirmed → profile repopulated from the new resume.
          ref.invalidate(myProfileProvider);
          ref.invalidate(profileSummaryProvider);
          showSnackbar(
              context, "Resume updated. We've refreshed your profile from it.");
        } else {
          showSnackbar(
              context,
              "Resume updated. We're still reading it, your profile will "
              'update shortly.');
        }
        Navigator.of(context).pop(true);
      } else if (next.status == ResumeUploadStatus.error &&
          next.error != null) {
        showSnackbar(context, next.error!, isError: true);
      }
    });

    final busy = state.isBusy || _deleting;

    // Block drag/back dismissal while a replace upload or delete is in
    // flight — leaving mid-mutation would strand the card on stale state.
    return PopScope(
      canPop: !busy,
      child: ProfileSheetScaffold(
        title: 'Edit Resume',
        icon: Icons.description_outlined,
        tintedIcon: true,
        fullHeight: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FieldLabel('Resume Name'),
            const SizedBox(height: 8),
            _ResumeNameField(name: widget.resume.fileName),
            const SizedBox(height: 20),
            const _FieldLabel('Replace File'),
            const SizedBox(height: 8),
            _ReplaceFileZone(
              pickedName: state.hasLocalFile ? state.fileName : null,
              pickedSizeBytes: state.hasLocalFile ? state.fileSizeBytes : null,
              onTap: busy ? null : notifier.pickFile,
            ),
            if (state.isBusy) ...[
              const SizedBox(height: 16),
              _BusyRow(
                label: state.isParsing
                    ? 'Parsing your resume…'
                    : 'Uploading your resume…',
              ),
            ],
          ],
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Delete only when the record id is known (it always is per the
            // contract; defensive against a key-only record).
            if (widget.resume.id.isNotEmpty) ...[
              _DeleteResumeButton(
                deleting: _deleting,
                onTap: busy ? null : _confirmDelete,
              ),
              const SizedBox(height: 10),
            ],
            SheetPrimaryButton(
              label: state.isUploading
                  ? 'Uploading…'
                  : state.isParsing
                      ? 'Parsing your resume…'
                      : 'Update Resume',
              onTap: (state.hasLocalFile && !busy) ? _update : null,
              loading: state.isBusy,
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
    );
  }
}

/// Read-only current-file row (the backend keeps no editable display name —
/// renaming isn't a supported operation, so this is presentation only).
class _ResumeNameField extends StatelessWidget {
  const _ResumeNameField({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    // A read-only value, so a raised row rather than an input well.
    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(Icons.description_outlined,
              size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed pick zone: the empty state prompts "Choose new file"; once a file
/// is picked it shows name + size (tap again to change).
class _ReplaceFileZone extends StatelessWidget {
  const _ReplaceFileZone({
    required this.pickedName,
    required this.pickedSizeBytes,
    required this.onTap,
  });

  final String? pickedName;
  final int? pickedSizeBytes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final hasPick = pickedName != null;
    return DottedBorder(
      borderType: BorderType.RRect,
      radius: const Radius.circular(ProfileSurfaceTokens.nestedRadius),
      // The shared drop-zone edge in both states; a picked file is announced
      // by the glyph swap and the filename, not by the edge turning blue.
      color: tokens.uploadZoneBorder,
      strokeWidth: 1.4,
      dashPattern: const [4, 4],
      child: InkWell(
        borderRadius: BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            color: tokens.uploadZoneFill,
            borderRadius:
                BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
          ),
          child: Column(
            children: [
              Icon(
                hasPick ? Icons.description_outlined : Icons.upload_outlined,
                size: 26,
                color: hasPick ? tokens.controlInk : tokens.textTertiary,
              ),
              const SizedBox(height: 10),
              Text(
                hasPick ? pickedName! : 'Choose new file',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.controlInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasPick
                    ? '${_prettySize(pickedSizeBytes)} · tap to change'
                    : 'PDF, DOCX, or DOC · max 5 MB',
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

  static String _prettySize(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Selected';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// Honest in-flight status row (upload → parse), same treatment as the
/// sprint's "Uploading your intro…" line.
class _BusyRow extends StatelessWidget {
  const _BusyRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The sheet's destructive action: the app's destructive outline, full width,
/// with its own spinner while the delete is in flight.
class _DeleteResumeButton extends StatelessWidget {
  const _DeleteResumeButton({required this.deleting, required this.onTap});

  final bool deleting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton.destructive(
      label: deleting ? 'Deleting…' : 'Delete Resume',
      leading: Icons.delete_outline,
      loading: deleting,
      onPressed: onTap,
    );
  }
}
