import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/helpers/avatar_url.dart';
import '../../../core/helpers/user_handle.dart';
import '../../../core/router/profile_navigation.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/utils/form_validators.dart';
import '../../../core/widgets/cached_image.dart';
import '../data/models/profile_reference.dart';
import '../data/references_repository.dart';
import '../providers/profile_provider.dart';
import '../providers/references_provider.dart';
import 'profile_misc_widgets.dart';
import 'profile_section.dart';
import 'profile_sheet_kit.dart';
import 'profile_surface.dart';
import '../../../shared/widgets/app_button.dart';

/// References on the profile.
///
/// Owner and visitor read different endpoints with different payloads — the
/// owner list carries statuses (and the reviewer's email, for legacy rows),
/// the public list carries only published testimonials. They are separate
/// models and separate branches here so owner-only fields have no path onto
/// someone else's profile.
class ReferencesSectionCard extends ConsumerWidget {
  const ReferencesSectionCard({
    super.key,
    required this.editable,
    this.userIdOrHandle,
  });

  final bool editable;

  /// Whose references to show when [editable] is false. This endpoint resolves
  /// either the public handle or the auth UUID.
  final String? userIdOrHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return editable ? _ownerBody(context, ref) : _publicBody(context, ref);
  }

  Widget _ownerBody(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myReferencesProvider);
    final incoming =
        ref.watch(incomingReferenceRequestsProvider).value ?? const [];
    final rows = async.value ?? const <ProfileReference>[];
    return _frame(
      context,
      hasEntries: rows.isNotEmpty,
      onTap: () => openReferencesSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The inbox leads: someone is waiting on this person, and there is
          // no push notification for it on mobile (the website synthesises
          // that in its own BFF), so the profile is where it has to surface.
          if (incoming.isNotEmpty)
            _IncomingBanner(
              count: incoming.length,
              onTap: () => openReferencesSheet(context),
            ),
          async.when(
            loading: () => const _RefLoading(),
            error: (e, _) => SectionErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(myReferencesProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const SectionEmptyState(
                  icon: Icons.format_quote,
                  title: 'No references yet',
                  subtitle:
                      'Request one from a colleague or manager on SyncUp.',
                );
              }
              // EVERY row, each as its own card — not just the published ones
              // behind a single "waiting for a reply" banner. A request the
              // user sent is a thing that is happening to a named person, and
              // the owner needs to see who, what state it is in, and be able
              // to open their profile. This matches the website's own
              // ReferenceCard, which also renders every status.
              return Column(
                children: [
                  // Named `entry`, not `ref` — that would shadow the WidgetRef
                  // this closure also uses.
                  ...withFoldMark([
                    for (final entry in items)
                      OwnerReferenceRow(
                        reference: entry,
                        onOpenReviewer: _reviewerTapFor(context, entry),
                      ),
                  ]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _publicBody(BuildContext context, WidgetRef ref) {
    final identifier = userIdOrHandle?.trim() ?? '';
    if (identifier.isEmpty) return const SizedBox.shrink();
    final async = ref.watch(publicReferencesProvider(identifier));
    final items = async.value ?? const <PublicProfileReference>[];
    // Nothing to say about a stranger with no references — stay silent rather
    // than rendering an empty card on their profile.
    if (items.isEmpty) return const SizedBox.shrink();
    return _frame(
      context,
      hasEntries: true,
      onTap: null,
      child: Column(
        children: [
          for (final item in items)
            _ReferenceQuote(
              name: item.reviewerName,
              context_: item.contextLine,
              text: item.reviewText,
              avatarUrl: item.reviewer?.profilePic,
            ),
        ],
      ),
    );
  }

  /// Opens the reviewer's public profile, or null when there is nothing safe
  /// to open.
  ///
  /// The route resolves a **handle**, so a payload that fell back to a UUID
  /// would push a screen that 404s — `isPublicProfileHandle` gates that, the
  /// same way every other profile navigation in the app does.
  static VoidCallback? _reviewerTapFor(
    BuildContext context,
    ProfileReference reference,
  ) {
    final handle = reference.reviewer?.handle.trim() ?? '';
    if (!isPublicProfileHandle(handle)) return null;
    return () => openPublicProfile(context, userId: handle);
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
            icon: Icons.format_quote,
            title: 'References',
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

/// A published testimonial. Identical rendering for owner and visitor — the
/// fields it reads exist on both payloads.
class _ReferenceQuote extends StatelessWidget {
  const _ReferenceQuote({
    required this.name,
    required this.context_,
    required this.text,
    this.avatarUrl,
  });

  final String name;
  final String context_;
  final String? text;
  final String? avatarUrl;

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
            children: [
              ReferenceAvatar(url: avatarUrl, name: name, size: 30),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if (context_.isNotEmpty)
                      Text(
                        context_,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if ((text ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text!.trim(),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: colors.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular avatar with an initial fallback, sized for reference rows.
class ReferenceAvatar extends StatelessWidget {
  const ReferenceAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 34,
  });

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final resolved = sanitizeAvatarUrl(url ?? '');
    if (resolved.isNotEmpty) {
      return ClipOval(
        child: AppNetworkImage(
          url: resolved,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final tokens = context.tokensOrDefault;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.iconTile,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
      ),
    );
  }
}

class _IncomingBanner extends StatelessWidget {
  const _IncomingBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: tokens.infoContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.mark_email_unread_outlined,
                    size: 16, color: tokens.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    count == 1
                        ? '1 person asked you for a reference'
                        : '$count people asked you for a reference',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.info,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: tokens.info),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One reference on the **owner's** profile, in any status.
///
/// Deliberately not the quote card: an approved reference is a testimonial,
/// but a requested / declined / expired one is a piece of state the owner is
/// tracking. Both need the same anchor — who it involves — so this row leads
/// with the reviewer, carries the status pill, and then shows either the
/// testimonial or the per-status line explaining what is happening.
class OwnerReferenceRow extends StatelessWidget {
  const OwnerReferenceRow({
    super.key,
    required this.reference,
    this.onOpenReviewer,
  });

  final ProfileReference reference;

  /// Null when the reviewer has no usable public handle — the name then stays
  /// plain text rather than looking tappable and going nowhere.
  final VoidCallback? onOpenReviewer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final quote = (reference.reviewText ?? '').trim();
    final statusLine = reference.statusLine(formatDate: formatCooldownDate);
    final subtitle = reference.contextLine;
    final relationship = reference.relationship?.trim() ?? '';
    final firstName = reference.reviewerName.trim().split(' ').first;

    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReferenceAvatar(
                url: reference.reviewer?.profilePic,
                name: reference.reviewerName,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: onOpenReviewer,
                            child: Text(
                              reference.reviewerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ReferenceStatusPill(
                          status: reference.status,
                          isExpired: reference.isExpired,
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tokens.textTertiary,
                        ),
                      ),
                    ],
                    // How the owner described the working relationship when
                    // they asked — "Worked at SyncUp".
                    if (relationship.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        relationship,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (quote.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              '“$quote”',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: colors.onSurface,
              ),
            ),
          ] else if (statusLine != null) ...[
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule, size: 13, color: tokens.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    statusLine,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                      color: tokens.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (onOpenReviewer != null) ...[
            const SizedBox(height: 2),
            Semantics(
              button: true,
              label: "View $firstName's profile",
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onOpenReviewer,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  // The link is small type; the target is not.
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    "View $firstName's profile →",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefLoading extends StatelessWidget {
  const _RefLoading();

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

// ════════════════════════════════════════════════════════════════════════════
// Sheets
// ════════════════════════════════════════════════════════════════════════════

/// Manage references: the inbox of requests to answer, plus the user's own
/// outgoing requests and published references.
///
/// One sheet for both, with the inbox pinned above the user's own list — so
/// the banner that brings someone here lands them on what they came for
/// without needing a tab or a scroll target.
Future<void> openReferencesSheet(BuildContext context) {
  return showProfileSheet(
    context,
    fullHeight: true,
    builder: (_) => const _ReferencesSheet(),
  );
}

class _ReferencesSheet extends ConsumerStatefulWidget {
  const _ReferencesSheet();

  @override
  ConsumerState<_ReferencesSheet> createState() => _ReferencesSheetState();
}

class _ReferencesSheetState extends ConsumerState<_ReferencesSheet> {
  String? _busyId;

  // The child sheets invalidate the providers this sheet watches, so the list
  // behind them refreshes on its own — no local mirroring needed.
  Future<void> _request() => showProfileSheet<bool>(
        context,
        fullHeight: true,
        builder: (_) => const _RequestReferenceSheet(),
      );

  Future<void> _provide(IncomingReferenceRequest request) =>
      showProfileSheet<bool>(
        context,
        fullHeight: true,
        builder: (_) => _ProvideReferenceSheet(request: request),
      );

  Future<void> _run(
      String id, Future<void> Function() action, String success) async {
    setState(() => _busyId = id);
    try {
      await action();
      invalidateOwnerReferencesFrom(ref);
      if (!mounted) return;
      setState(() => _busyId = null);
      context.showSnackBar(success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(referencesRepositoryProvider);
    final mine = ref.watch(myReferencesProvider);
    final incoming = ref.watch(incomingReferenceRequestsProvider);
    final busy = _busyId != null;

    return ProfileSheetScaffold(
      title: 'References',
      icon: Icons.format_quote,
      tintedIcon: false,
      fullHeight: true,
      doneLabel: 'Done',
      onDone: busy ? null : () => Navigator.of(context).pop(),
      footer: SheetPrimaryButton(
        label: 'Request a Reference',
        onTap: busy ? null : _request,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          incoming.when(
            loading: () => const SizedBox.shrink(),
            // A failing inbox must not take the whole sheet down — the user's
            // own references below are a separate call.
            error: (_, __) => const SizedBox.shrink(),
            data: (requests) => requests.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SheetSectionLabel('Asked of you'),
                      const SizedBox(height: 10),
                      for (final request in requests)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _IncomingRequestCard(
                            request: request,
                            busy: busy,
                            onWrite: () => _provide(request),
                            onDecline: () => _run(
                              request.id,
                              () => repo.rejectReference(request.id),
                              'Request declined',
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
          const SheetSectionLabel('Your references'),
          const SizedBox(height: 10),
          mine.when(
            loading: () => const _RefLoading(),
            error: (e, _) => SectionErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(myReferencesProvider),
            ),
            data: (items) => items.isEmpty
                ? const _SheetHint(
                    text:
                        'No references yet. Request one from someone you have '
                        'worked with.',
                  )
                : Column(
                    children: [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _OwnerReferenceCard(
                            reference: item,
                            busy: busy,
                            onDelete: () => _run(
                              item.id,
                              () => repo.deleteReference(item.id),
                              'Reference removed',
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

class _IncomingRequestCard extends StatelessWidget {
  const _IncomingRequestCard({
    required this.request,
    required this.busy,
    required this.onWrite,
    required this.onDecline,
  });

  final IncomingReferenceRequest request;
  final bool busy;
  final VoidCallback onWrite;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReferenceAvatar(
                url: request.requester?.profilePic,
                name: request.requesterName,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.requesterName,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if ((request.requester?.title ?? '').isNotEmpty)
                      Text(
                        request.requester!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tokens.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if ((request.relationship ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Says you worked together as: ${request.relationship}',
              style: TextStyle(fontSize: 11.5, color: tokens.textTertiary),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              // The compact buttons, not the full sheet CTA — this is an
              // inline card action, and the footer button's weight would
              // dominate the card it sits in.
              Expanded(
                child: AppButton.primary(
                  label: 'Write reference',
                  size: AppButtonSize.compact,
                  onPressed: busy ? null : onWrite,
                ),
              ),
              const SizedBox(width: 10),
              AppButton.secondary(
                label: 'Decline',
                expand: false,
                size: AppButtonSize.compact,
                onPressed: busy ? null : onDecline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnerReferenceCard extends StatelessWidget {
  const _OwnerReferenceCard({
    required this.reference,
    required this.busy,
    required this.onDelete,
  });

  final ProfileReference reference;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final cooldown = reference.canRequestAgainAt;
    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReferenceAvatar(
                url: reference.reviewer?.profilePic,
                name: reference.reviewerName,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reference.reviewerName,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ReferenceStatusPill(
                      status: reference.status,
                      isExpired: reference.isExpired,
                    ),
                  ],
                ),
              ),
              // Hidden rather than disabled where the server refuses: an open
              // or declined SyncUp request can't be deleted, because removing
              // it would erase the record the cooldown is computed from.
              if (reference.isDeletable)
                IconButton(
                  onPressed: busy ? null : onDelete,
                  tooltip: 'Remove reference',
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: tokens.destructiveInk),
                ),
            ],
          ),
          if ((reference.reviewText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reference.reviewText!.trim(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: colors.onSurface,
              ),
            ),
          ],
          if (cooldown != null) ...[
            const SizedBox(height: 6),
            Text(
              'You can ask again after ${formatCooldownDate(cooldown)}.',
              style: TextStyle(fontSize: 11, color: tokens.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Status pill for an owner's reference row.
class ReferenceStatusPill extends StatelessWidget {
  const ReferenceStatusPill({
    super.key,
    required this.status,
    this.isExpired = false,
  });

  final ReferenceStatus status;

  /// The server also flags a still-REQUESTED row whose token lapsed but that
  /// hasn't been swept to EXPIRED yet; treat it as expired for display.
  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final effective = isExpired && status == ReferenceStatus.requested
        ? ReferenceStatus.expired
        : status;
    final (Color fill, Color ink) = switch (effective) {
      ReferenceStatus.approved => (
          tokens.successContainer,
          tokens.onSuccessContainer,
        ),
      ReferenceStatus.rejected => (
          colors.error.withValues(alpha: 0.12),
          colors.error,
        ),
      ReferenceStatus.pending => (
          tokens.infoContainer,
          tokens.info,
        ),
      ReferenceStatus.requested => (
          tokens.warningContainer,
          tokens.onWarningContainer,
        ),
      ReferenceStatus.expired || ReferenceStatus.unknown => (
          colors.surfaceContainerHighest,
          tokens.textTertiary,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        effective.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
  }
}

/// "14 Sep 2026" — the app's own format. The server's cooldown message embeds
/// a JS `toDateString()` ("Sun Sep 14 2026"), which appears nowhere else in
/// the product.
String formatCooldownDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// Search for a SyncUp member and ask them for a reference.
class _RequestReferenceSheet extends ConsumerStatefulWidget {
  const _RequestReferenceSheet();

  @override
  ConsumerState<_RequestReferenceSheet> createState() =>
      _RequestReferenceSheetState();
}

class _RequestReferenceSheetState
    extends ConsumerState<_RequestReferenceSheet> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _relationship = TextEditingController();

  Timer? _debounce;
  List<ReferenceSearchResult> _results = const [];
  ReferenceSearchResult? _selected;
  bool _searching = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _relationship.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (_selected != null) setState(() => _selected = null);
    final term = value.trim();
    if (term.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _runSearch(term));
  }

  Future<void> _runSearch(String term) async {
    final me = ref.read(myProfileProvider).value;
    final results = await ref.read(referencesRepositoryProvider).searchMembers(
          term,
          // Both identifiers, because the search rows carry both and the
          // request endpoint 400s on a self-request either way.
          excludeUserId: me?.id,
          excludeHandle: me?.userId,
        );
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _send() async {
    final target = _selected;
    if (target == null) {
      setState(() => _error = 'Search and pick a SyncUp profile first.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(referencesRepositoryProvider).requestReference(
            targetUserId: target.targetUserId,
            relationship: _relationship.text,
          );
      invalidateOwnerReferencesFrom(ref);
      if (!mounted) return;
      context.showSnackBar('Reference request sent to ${target.name}');
      Navigator.of(context).pop(true);
    } on ReferenceCooldownException catch (e) {
      if (!mounted) return;
      final when = e.canRequestAgainAt;
      setState(() {
        _sending = false;
        _error = when == null
            ? e.message
            : 'They declined your last request. You can ask again after '
                '${formatCooldownDate(when)}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        // Covers the rest of the server's refusals verbatim: asking yourself,
        // a profile that can't be found (which is also what a block looks
        // like — deliberately indistinguishable), and an already-open request.
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return ProfileSheetScaffold(
      title: 'Request a Reference',
      icon: Icons.format_quote,
      fullHeight: true,
      showBack: true,
      footer: SheetPrimaryButton(
        label: _sending ? 'Sending…' : 'Send Request',
        onTap: _sending || _selected == null ? null : _send,
        loading: _sending,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTextField(
            label: 'Who are you asking?',
            hint: 'Search by name',
            controller: _search,
            leadingIcon: Icons.search,
            onChanged: _onQueryChanged,
          ),
          const SizedBox(height: 12),
          if (_selected != null)
            _SelectedMemberRow(
              member: _selected!,
              onClear: () => setState(() {
                _selected = null;
                _search.clear();
              }),
            )
          else if (_searching)
            const _RefLoading()
          else if (_search.text.trim().isNotEmpty && _results.isEmpty)
            _SheetHint(
                text: 'No SyncUp members match "${_search.text.trim()}".')
          else
            for (final member in _results)
              _MemberResultRow(
                member: member,
                onTap: () => setState(() {
                  _selected = member;
                  _search.text = member.name;
                  _results = const [];
                  _error = null;
                }),
              ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'How do you know them?',
            hint: 'e.g. Reported to me at SyncUp',
            controller: _relationship,
            maxLength: 100,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.errorContainer.withValues(alpha: 0.5),
                  borderRadius: AppRadii.controlAll,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: colors.error,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'They can write a reference or decline. Approved references show '
            'on your profile.',
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

class _MemberResultRow extends StatelessWidget {
  const _MemberResultRow({required this.member, required this.onTap});

  final ReferenceSearchResult member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            ReferenceAvatar(url: member.profilePic, name: member.name),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  if (member.title.isNotEmpty)
                    Text(
                      member.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: tokens.textTertiary,
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

class _SelectedMemberRow extends StatelessWidget {
  const _SelectedMemberRow({required this.member, required this.onClear});

  final ReferenceSearchResult member;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      child: Row(
        children: [
          ReferenceAvatar(url: member.profilePic, name: member.name),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              member.name,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
          IconButton(
            onPressed: onClear,
            tooltip: 'Choose someone else',
            icon: Icon(Icons.close, size: 18, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Write the reference someone asked for. Publishes immediately on send —
/// there is no second approval step for a SyncUp-to-SyncUp reference.
class _ProvideReferenceSheet extends ConsumerStatefulWidget {
  const _ProvideReferenceSheet({required this.request});

  final IncomingReferenceRequest request;

  @override
  ConsumerState<_ProvideReferenceSheet> createState() =>
      _ProvideReferenceSheetState();
}

class _ProvideReferenceSheetState
    extends ConsumerState<_ProvideReferenceSheet> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _company = TextEditingController();

  bool _sending = false;
  String? _textError;

  @override
  void initState() {
    super.initState();
    // Pre-fill the writer's own attribution from their profile; they can edit
    // it. The *author* is taken from the session server-side either way, so
    // these two fields only affect how the reference is captioned.
    final me = ref.read(myProfileProvider).value;
    if (me != null) {
      _title.text = me.title;
      _company.text = me.company;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (FormValidators.requiredField(_text.text) != null) {
      setState(() => _textError = 'Write a few words to continue.');
      return;
    }
    setState(() {
      _sending = true;
      _textError = null;
    });
    try {
      await ref.read(referencesRepositoryProvider).provideReference(
            widget.request.id,
            reviewText: _text.text,
            reviewerTitle: _title.text,
            reviewerCompany: _company.text,
          );
      invalidateOwnerReferencesFrom(ref);
      if (!mounted) return;
      context.showSnackBar('Reference sent');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final name = widget.request.requesterName;
    return ProfileSheetScaffold(
      title: 'Write a Reference',
      subtitle: 'For $name',
      icon: Icons.format_quote,
      fullHeight: true,
      showBack: true,
      footer: SheetPrimaryButton(
        label: _sending ? 'Sending…' : 'Send Reference',
        onTap: _sending ? null : _send,
        loading: _sending,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTextField(
            label: 'Your reference',
            hint: 'What was it like working with $name?',
            controller: _text,
            maxLines: 6,
            maxLength: 2000,
            showCounter: true,
            errorText: _textError,
            onChanged: (_) {
              if (_textError != null) setState(() => _textError = null);
            },
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Your title',
            hint: 'Optional',
            controller: _title,
            maxLength: 120,
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Your company',
            hint: 'Optional',
            controller: _company,
            maxLength: 120,
          ),
          const SizedBox(height: 14),
          Text(
            'This publishes on $name\'s profile right away, under your name.',
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

class _SheetHint extends StatelessWidget {
  const _SheetHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style:
            TextStyle(fontSize: 12, height: 1.35, color: tokens.textTertiary),
      ),
    );
  }
}
