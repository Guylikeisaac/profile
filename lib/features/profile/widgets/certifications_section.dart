import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/utils/form_validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/month_year_picker.dart';
import '../data/certifications_repository.dart';
import '../data/models/certification.dart';
import '../providers/certifications_provider.dart';
import 'profile_misc_widgets.dart';
import 'profile_section.dart';
import 'profile_sheet_kit.dart';
import 'profile_surface.dart';

/// Certifications on the profile.
///
/// Two sources, never mixed: the owner reads `/certifications/me` (every row,
/// with its verification state), a visitor reads `/certifications/public/{id}`
/// (VERIFIED rows only, with no status or rejection reason on the wire). The
/// widget picks by [editable] rather than filtering a shared list, so an
/// owner-only field can't leak onto someone else's profile by accident.
class CertificationsSectionCard extends ConsumerWidget {
  const CertificationsSectionCard({
    super.key,
    required this.editable,
    this.userUuid,
  });

  final bool editable;

  /// The profile owner's internal auth UUID. Required for the public read —
  /// that endpoint does not resolve an `@handle`.
  final String? userUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return editable ? _ownerBody(context, ref) : _publicBody(context, ref);
  }

  Widget _ownerBody(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myCertificationsProvider);
    return _frame(
      context,
      hasEntries: async.value?.isNotEmpty ?? false,
      onTap: () => openCertificationsSheet(context),
      child: async.when(
        loading: () => const _CertLoading(),
        error: (e, _) => SectionErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(myCertificationsProvider),
        ),
        data: (items) => items.isEmpty
            ? const SectionEmptyState(
                icon: Icons.workspace_premium_outlined,
                title: 'Add your certifications',
                subtitle: 'Upload proof and get them verified.',
              )
            : Column(
                children: [
                  ...withFoldMark(visible: 2, [
                    for (final cert in items)
                      _OwnerCertTile(certification: cert),
                  ]),
                ],
              ),
      ),
    );
  }

  Widget _publicBody(BuildContext context, WidgetRef ref) {
    final uuid = userUuid?.trim() ?? '';
    if (uuid.isEmpty) return const SizedBox.shrink();
    final async = ref.watch(publicCertificationsProvider(uuid));
    final items = async.value ?? const <PublicCertification>[];
    if (async.isLoading && items.isEmpty) return const SizedBox.shrink();
    return _frame(
      context,
      hasEntries: items.isNotEmpty,
      onTap: null,
      // Unlike References — which the website hides outright when a visitor
      // has none — Certifications keeps its card and says so. Verified
      // credentials are a claim people look for, so "none" is information;
      // the copy is the website's own.
      child: items.isEmpty
          ? const SectionEmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'No verified certifications',
              subtitle: 'This user has not added any verified certifications.',
            )
          : Column(
              children: [
                ...withFoldMark(visible: 2, [
                  for (final cert in items)
                    _PublicCertTile(certification: cert),
                ]),
              ],
            ),
    );
  }

  Widget _frame(
    BuildContext context, {
    required bool hasEntries,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.workspace_premium_outlined,
            title: 'Certifications',
            showAdd: editable && !hasEntries,
            showEdit: editable && hasEntries,
            onAdd: onTap,
            onEdit: onTap,
          ),
          child,
        ],
      ),
    );
  }
}

/// Owner row: name, issuer, dates, verification pill, and the reviewer's
/// reason when a claim was turned down.
class _OwnerCertTile extends StatelessWidget {
  const _OwnerCertTile({required this.certification});

  final Certification certification;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  certification.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CertificationStatusPill(status: certification.status),
            ],
          ),
          if ((certification.issuingOrganization ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              certification.issuingOrganization!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (certificationDateLine(
            certification.issueDate,
            certification.expirationDate,
          )
              case final line?) ...[
            const SizedBox(height: 4),
            Text(
              line,
              style: TextStyle(fontSize: 11, color: tokens.textTertiary),
            ),
          ],
          if (certification.hasDocument) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.attach_file, size: 13, color: tokens.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    certification.documentName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: tokens.textTertiary),
                  ),
                ),
              ],
            ),
          ],
          // Owner-only. The public payload has no rejection reason at all, so
          // this can never render on a visitor's screen.
          if (certification.status == CertificationStatus.rejected &&
              (certification.rejectionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.5),
                borderRadius: AppRadii.smallAll,
              ),
              child: Text(
                certification.rejectionReason!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: colors.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublicCertTile extends StatelessWidget {
  const _PublicCertTile({required this.certification});

  final PublicCertification certification;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  certification.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Every row on this route is verified by definition, so the
              // badge is a statement, not a status read off the payload.
              const CertificationStatusPill(
                  status: CertificationStatus.verified),
            ],
          ),
          if ((certification.issuingOrganization ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              certification.issuingOrganization!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (certificationDateLine(
            certification.issueDate,
            certification.expirationDate,
          )
              case final line?) ...[
            const SizedBox(height: 4),
            Text(
              line,
              style: TextStyle(fontSize: 11, color: tokens.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Verification pill. Green = verified, amber = in review, red = rejected.
class CertificationStatusPill extends StatelessWidget {
  const CertificationStatusPill({super.key, required this.status});

  final CertificationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final (Color fill, Color ink, IconData icon) = switch (status) {
      CertificationStatus.verified => (
          tokens.successContainer,
          tokens.onSuccessContainer,
          Icons.verified_outlined,
        ),
      CertificationStatus.rejected => (
          colors.error.withValues(alpha: 0.12),
          colors.error,
          Icons.error_outline,
        ),
      CertificationStatus.pending => (
          tokens.warningContainer,
          tokens.onWarningContainer,
          Icons.schedule,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: ink),
          const SizedBox(width: 3),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Mar 2024 – Mar 2027" / "Mar 2024" / null when neither date is set.
String? certificationDateLine(DateTime? issued, DateTime? expires) {
  final from = issued == null ? '' : formatMonthYear(issued);
  final to = expires == null ? '' : formatMonthYear(expires);
  if (from.isEmpty && to.isEmpty) return null;
  if (from.isEmpty) return 'Expires $to';
  if (to.isEmpty) return from;
  return '$from – $to';
}

// ════════════════════════════════════════════════════════════════════════════
// Sheets
// ════════════════════════════════════════════════════════════════════════════

/// Manage list: add, edit, and delete the signed-in user's certifications.
Future<void> openCertificationsSheet(BuildContext context) {
  return showProfileSheet(context,
      builder: (_) => const _CertificationsSheet());
}

class _CertificationsSheet extends ConsumerStatefulWidget {
  const _CertificationsSheet();

  @override
  ConsumerState<_CertificationsSheet> createState() =>
      _CertificationsSheetState();
}

class _CertificationsSheetState extends ConsumerState<_CertificationsSheet> {
  String? _deletingId;

  // The form invalidates `myCertificationsProvider`, which this sheet watches,
  // so the list behind it refreshes on its own.
  Future<void> _openForm({Certification? initial}) => showProfileSheet<bool>(
        context,
        fullHeight: true,
        builder: (_) => _CertificationFormSheet(initial: initial),
      );

  Future<void> _delete(Certification cert) async {
    setState(() => _deletingId = cert.id);
    try {
      await ref.read(certificationsRepositoryProvider).delete(cert.id);
      ref.invalidate(myCertificationsProvider);
      if (!mounted) return;
      setState(() => _deletingId = null);
      context.showSnackBar('Certification removed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingId = null);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myCertificationsProvider);
    final busy = _deletingId != null;
    return ProfileSheetScaffold(
      title: 'Certifications',
      icon: Icons.workspace_premium_outlined,
      tintedIcon: false,
      doneLabel: 'Done',
      onDone: busy ? null : () => Navigator.of(context).pop(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          async.when(
            loading: () => const _CertLoading(),
            error: (e, _) => SectionErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(myCertificationsProvider),
            ),
            data: (items) => Column(
              children: [
                for (final cert in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CertManageCard(
                      certification: cert,
                      busy: busy,
                      onEdit: () => _openForm(initial: cert),
                      onDelete: () => _delete(cert),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          SheetOutlinedAddButton(
            label: 'Add Certification',
            onTap: busy ? null : () => _openForm(),
          ),
        ],
      ),
    );
  }
}

class _CertManageCard extends StatelessWidget {
  const _CertManageCard({
    required this.certification,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final Certification certification;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  certification.name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                CertificationStatusPill(status: certification.status),
                if (!certification.isDeletable) ...[
                  const SizedBox(height: 6),
                  Text(
                    // Says why the bin is missing rather than offering a
                    // button the API answers with a 400.
                    "Verified certifications can't be removed.",
                    style: TextStyle(fontSize: 11, color: tokens.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (certification.isDeletable)
            SheetRowActions(
              onEdit: busy ? () {} : onEdit,
              onDelete: busy ? () {} : onDelete,
            )
          else
            IconButton(
              onPressed: busy ? null : onEdit,
              tooltip: 'Edit certification',
              icon:
                  Icon(Icons.edit_outlined, size: 18, color: tokens.controlInk),
            ),
        ],
      ),
    );
  }
}

/// Add / edit one certification, including the optional proof document.
class _CertificationFormSheet extends ConsumerStatefulWidget {
  const _CertificationFormSheet({this.initial});

  final Certification? initial;

  @override
  ConsumerState<_CertificationFormSheet> createState() =>
      _CertificationFormSheetState();
}

class _CertificationFormSheetState
    extends ConsumerState<_CertificationFormSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _org =
      TextEditingController(text: widget.initial?.issuingOrganization ?? '');
  late final TextEditingController _credentialId =
      TextEditingController(text: widget.initial?.credentialId ?? '');
  late final TextEditingController _credentialUrl =
      TextEditingController(text: widget.initial?.credentialUrl ?? '');

  late DateTime? _issued = widget.initial?.issueDate;
  late DateTime? _expires = widget.initial?.expirationDate;

  /// A newly picked file, not yet uploaded.
  CertificationDocument? _picked;

  /// True when the user detached the stored document without picking a new one.
  bool _documentRemoved = false;

  bool _saving = false;
  String? _nameError;
  String? _urlError;
  String? _expiresError;

  @override
  void dispose() {
    _name.dispose();
    _org.dispose();
    _credentialId.dispose();
    _credentialUrl.dispose();
    super.dispose();
  }

  String? get _existingDocumentName =>
      _documentRemoved ? null : widget.initial?.documentName;

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: CertificationDocumentRules.allowedExtensions,
    );
    final file = result?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null) return;

    final extension = file.extension?.toLowerCase() ??
        (file.name.contains('.') ? file.name.split('.').last : '');
    final contentType = CertificationDocumentRules.mimeForExtension(extension);
    // Checked before the presign so an unusable file costs no round trip and
    // no signature — same verdict the server would return.
    final reason = CertificationDocumentRules.validate(
      sizeBytes: file.size,
      contentType: contentType,
    );
    if (reason != null) {
      if (mounted) context.showErrorSnackBar(reason);
      return;
    }
    setState(() {
      _picked = CertificationDocument(
        filePath: path,
        fileName: file.name,
        sizeBytes: file.size,
        contentType: contentType,
      );
      _documentRemoved = false;
    });
  }

  Future<void> _pickIssued() async {
    final picked = await showMonthYearPicker(context,
        initial: _issued, title: 'Issue date');
    if (picked != null) {
      setState(() {
        _issued = picked;
        _expiresError = null;
      });
    }
  }

  Future<void> _pickExpires() async {
    final picked = await showMonthYearPicker(context,
        initial: _expires ?? _issued, title: 'Expiry date');
    if (picked != null) {
      setState(() {
        _expires = picked;
        _expiresError = null;
      });
    }
  }

  bool _validate() {
    final nameError = FormValidators.requiredField(_name.text) == null
        ? null
        : 'Add a certification name to continue.';
    final url = _credentialUrl.text.trim();
    // The schema validates this with Zod's `.url()`, which wants a complete
    // URL — a bare "coursera.org/verify/x" is a 400. Catch it here so the
    // user gets a field-level message instead of a failed save.
    final urlError = url.isEmpty || _isFullUrl(url)
        ? null
        : 'Enter a full link, including https://';
    final expiresError =
        (_issued != null && _expires != null && _expires!.isBefore(_issued!))
            ? "Expiry can't be before the issue date."
            : null;
    setState(() {
      _nameError = nameError;
      _urlError = urlError;
      _expiresError = expiresError;
    });
    return nameError == null && urlError == null && expiresError == null;
  }

  static bool _isFullUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        (uri.host.isNotEmpty);
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final repo = ref.read(certificationsRepositoryProvider);
    final input = CertificationInput(
      name: _name.text,
      issuingOrganization: _org.text,
      issueDate: _issued,
      expirationDate: _expires,
      credentialId: _credentialId.text,
      credentialUrl: _credentialUrl.text,
    );

    setState(() => _saving = true);
    try {
      final editing = widget.initial != null;
      if (editing) {
        await repo.update(
          widget.initial!.id,
          input,
          document: _picked,
          removeDocument: _documentRemoved && _picked == null,
        );
      } else {
        await repo.create(input, document: _picked);
      }
      ref.invalidate(myCertificationsProvider);
      if (!mounted) return;
      context.showSnackBar(
        editing ? 'Certification saved' : 'Certification submitted for review',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final editing = widget.initial != null;
    return ProfileSheetScaffold(
      title: 'Certification',
      icon: Icons.workspace_premium_outlined,
      fullHeight: true,
      showBack: true,
      footer: SheetPrimaryButton(
        label: _saving
            ? 'Saving…'
            : (editing ? 'Save Certification' : 'Add Certification'),
        onTap: _saving ? null : _submit,
        loading: _saving,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTextField(
            label: 'Name',
            hint: 'e.g. AWS Solutions Architect',
            controller: _name,
            maxLength: 120,
            errorText: _nameError,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Issuing Organization',
            hint: 'e.g. Amazon Web Services',
            controller: _org,
            maxLength: 120,
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SheetDateField(
                  label: 'Issued',
                  hint: 'Select month',
                  value: formatMonthYear(_issued),
                  onTap: _pickIssued,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SheetDateField(
                  label: 'Expires',
                  hint: 'Select month',
                  value: formatMonthYear(_expires),
                  onTap: _pickExpires,
                  errorText: _expiresError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Credential ID',
            hint: 'Optional',
            controller: _credentialId,
            maxLength: 100,
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Credential URL',
            hint: 'https://…',
            controller: _credentialUrl,
            keyboardType: TextInputType.url,
            maxLength: 500,
            errorText: _urlError,
            onChanged: (_) {
              if (_urlError != null) setState(() => _urlError = null);
            },
          ),
          const SizedBox(height: 20),
          _DocumentPickerRow(
            pickedName: _picked?.fileName,
            existingName: _existingDocumentName,
            onPick: _saving ? null : _pickDocument,
            onRemove: _saving
                ? null
                : () => setState(() {
                      _picked = null;
                      _documentRemoved = true;
                    }),
          ),
          const SizedBox(height: 10),
          Text(
            widget.initial?.editResetsVerification == true
                ? 'Saving sends this certification back for review.'
                : 'An admin reviews your proof before the certification shows '
                    'as verified.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: tokens.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Attach / replace / remove the proof document.
class _DocumentPickerRow extends StatelessWidget {
  const _DocumentPickerRow({
    required this.pickedName,
    required this.existingName,
    required this.onPick,
    required this.onRemove,
  });

  final String? pickedName;
  final String? existingName;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final name = pickedName ?? existingName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proof Document',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        if (name == null)
          SheetOutlinedAddButton(label: 'Attach PDF or image', onTap: onPick)
        else
          ProfileSurface(
            tier: ProfileSurfaceTier.raised,
            padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
            child: Row(
              children: [
                Icon(Icons.description_outlined,
                    size: 16, color: tokens.iconInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                AppButton.text(label: 'Replace', onPressed: onPick),
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Remove document',
                  icon:
                      Icon(Icons.close, size: 18, color: tokens.destructiveInk),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'PDF, JPG, PNG or WEBP · up to 10 MB',
          style: TextStyle(fontSize: 11, color: tokens.textTertiary),
        ),
      ],
    );
  }
}

class _CertLoading extends StatelessWidget {
  const _CertLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
