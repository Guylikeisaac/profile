import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_manager.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/data/repository_exception.dart';
import '../../../core/helpers/avatar_url.dart';
import '../../../core/helpers/format_count.dart';
import '../../../core/helpers/post_ownership.dart';
import '../../../core/helpers/snackbar_helper.dart';
import '../../../core/router/profile_navigation.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/confirm_action_dialog.dart';
import '../../blocked_users/widgets/block_author_dialog.dart';
import '../../chat/navigation/open_direct_chat.dart';
import '../../network/data/connection_repository.dart';
import '../../network/providers/network_providers.dart';
import '../../profile_menu/providers/profile_menu_provider.dart';
import '../../readiness_sprint/widgets/sprint_pending_card.dart';
import '../../report/data/models/report_models.dart';
import '../../report/widgets/report_content_sheet.dart';
import '../data/models/user_profile.dart';
import '../data/profile_view_data.dart';
import '../providers/activity_provider.dart';
import '../providers/certifications_provider.dart';
import '../providers/profile_posts_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/references_provider.dart';
import '../widgets/certifications_section.dart';
import '../widgets/profile_edit_sheets.dart';
import '../widgets/profile_hero.dart';
import '../widgets/profile_member_menu.dart';
import '../widgets/profile_mono_theme.dart';
import '../widgets/profile_motion.dart';
import '../widgets/profile_section.dart' show ProfileFoldingSections;
import '../widgets/profile_sheet_kit.dart'
    show ProfileSheetAction, showProfileActionSheet;
import '../widgets/references_section.dart';
import '../widgets/profile_view_sections.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/theme_context_ext.dart';

/// One profile rendered in three modes per the design spec:
/// [ProfileViewMode.selfView] (owner/edit surface), [ProfileViewMode.publicView]
/// (visitor/contact surface), and [ProfileViewMode.cv] (shareable export).
///
/// The hero + body sections are shared; [mode] decides which chrome, sections,
/// stat set, and affordances render — keeping the variants visually related but
/// behaviorally distinct.
class ProfileViewScreen extends StatelessWidget {
  const ProfileViewScreen({
    super.key,
    required this.mode,
    this.userId,
  });

  const ProfileViewScreen.self({super.key})
      : mode = ProfileViewMode.selfView,
        userId = null;

  /// [userId] = the other user's public handle (custom userId). When null, this
  /// shows the visitor-preview of the signed-in user's own profile (the Self
  /// View overflow uses this).
  const ProfileViewScreen.public({super.key, this.userId})
      : mode = ProfileViewMode.publicView;
  const ProfileViewScreen.cv({super.key})
      : mode = ProfileViewMode.cv,
        userId = null;

  final ProfileViewMode mode;
  final String? userId;

  /// Every rendering of the profile is strictly black and white, in both app
  /// theme modes — see [ProfileMonoTheme].
  @override
  Widget build(BuildContext context) =>
      ProfileMonoTheme(child: _ProfileView(mode: mode, userId: userId));
}

class _ProfileView extends ConsumerStatefulWidget {
  const _ProfileView({required this.mode, this.userId});

  final ProfileViewMode mode;
  final String? userId;

  @override
  ConsumerState<_ProfileView> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends ConsumerState<_ProfileView> {
  /// The list's scroll position, for the cover's parallax and the sticky bar.
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _offset.value = _scroll.offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _offset.dispose();
    super.dispose();
  }

  bool _introUploading = false;
  bool _leaveConfirmed = false;

  /// Optimistic override for the public-profile Connect button after an action
  /// (send / withdraw / accept), so the button reflects the change immediately
  /// without waiting for a re-fetch. Cleared on the next screen open.
  PublicConnectState? _connectOverride;
  bool _connectBusy = false;

  /// True when viewing another user's public profile (vs. the self preview).
  bool get _isOtherUser =>
      widget.mode == ProfileViewMode.publicView &&
      (widget.userId?.isNotEmpty ?? false);

  void _refreshProfile() {
    if (_isOtherUser) {
      ref.invalidate(publicProfileBundleProvider(widget.userId!));
    } else {
      ref.invalidate(myProfileProvider);
      // References and Certifications are separate fetches, so a pull-to-
      // refresh has to invalidate them explicitly or the user sees a stale
      // section beside a freshly-loaded profile. The reference inbox in
      // particular is pull-only — nothing pushes it — so this is the moment
      // it gets to notice a new request.
      invalidateOwnerReferencesFrom(ref);
      ref.invalidate(myCertificationsProvider);
    }
    // Activity's two tabs are two more independent fetches, on providers keyed
    // by the profile's UUID — which this method doesn't have on the public
    // branch (the route carries a handle). Invalidating each family whole
    // refreshes whichever instance the section is actually rendering.
    ref.invalidate(profilePostsProvider);
    ref.invalidate(activityFeedProvider);
  }

  /// Performs the connect/withdraw/accept action for the current relationship,
  /// optimistically updating the button and refreshing the other Network
  /// surfaces (People tab, Requests, Connections) so state stays in sync.
  /// [receiverId] must be the user's UUID (`connection/send`/`withdraw` expect a
  /// UUID receiver id, per the docs and live payloads), not the handle.
  Future<void> _runConnect(String receiverId, PublicConnectState st) async {
    final repo = ref.read(connectionRepositoryProvider);
    setState(() => _connectBusy = true);
    try {
      switch (st.kind) {
        case PublicConnectKind.none:
          await repo.sendConnection(receiverId);
          _connectOverride =
              const PublicConnectState(PublicConnectKind.outgoing);
        case PublicConnectKind.outgoing:
          await repo.withdrawConnection(receiverId);
          _connectOverride = const PublicConnectState(PublicConnectKind.none);
        case PublicConnectKind.incoming:
          await repo.updateConnection(st.connectionId, 'ACCEPTED');
          // Accepting keeps the same record, so its id carries over — without
          // it "Remove connection" would be missing until the next open.
          _connectOverride = PublicConnectState(
            PublicConnectKind.connected,
            connectionId: st.connectionId,
          );
        case PublicConnectKind.connected:
        case PublicConnectKind.self:
          break; // no action
      }
      // Reflect the change on every affected surface. Invalidating the accepted
      // list also refreshes the derived self count (selfConnectionCountProvider).
      ref.invalidate(peopleNetworkProvider);
      ref.invalidate(pendingRequestsProvider);
      ref.invalidate(acceptedConnectionsProvider);
      ref.invalidate(profileSummaryProvider);
      // A send/withdraw here changes the "Sent" tab (My Network) too.
      ref.invalidate(sentPendingRequestsProvider);
      ref.invalidate(sentPendingCountProvider);
    } catch (e) {
      if (mounted) {
        showSnackbar(
          context,
          e is RepositoryException
              ? e.message
              : 'Something went wrong. Try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _connectBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Other-user: fetch profile + connection status together so the hero renders
    // the correct Connect state on the first frame (no "Connect" flash).
    // Self: just the profile; the connection count is derived separately.
    final Widget body = _isOtherUser
        ? ref.watch(publicProfileBundleProvider(widget.userId!)).when(
              loading: () => const _ProfileSkeleton(),
              error: (error, _) => _ProfileErrorView(
                message: error.toString(),
                onRetry: _refreshProfile,
              ),
              data: (bundle) => _content(
                context,
                ref,
                bundle.profile,
                ProfileViewData.fromUserProfile(bundle.profile),
                relation: _connectOverride ?? bundle.connect,
              ),
            )
        : ref.watch(myProfileProvider).when(
              loading: () => const _ProfileSkeleton(),
              error: (error, _) => _ProfileErrorView(
                message: error.toString(),
                onRetry: _refreshProfile,
              ),
              data: (profile) => _content(
                context,
                ref,
                profile,
                ProfileViewData.fromUserProfile(profile),
                relation: null,
              ),
            );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: _leaveConfirmed || !_introUploading,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _introUploading) {
            _confirmLeaveWhileUploading();
          }
        },
        // No bottom nav and no FAB, in any mode: every flavour of this screen
        // is a full-screen route above the shell, so there is deliberately no
        // navigation here at all — Back is the way out.
        // The near-black canvas the whole profile is layered on — the same
        // ground as Home and Network. Every section card is one tonal step up
        // from this, so the page itself must never be a grey.
        child: Scaffold(
          backgroundColor: ProfileSurfaceTokens.of(context).canvas,
          extendBody: true,
          body: body,
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    ProfileViewData data, {
    required PublicConnectState? relation,
  }) {
    // Room under the last row: full-screen, there is no chrome to clear, only
    // the home indicator.
    final navSpace = MediaQuery.of(context).padding.bottom + 28;

    // Connect button from the real relationship (already resolved by the bundle
    // — no async watch here, so no wrong initial state). Self → hidden.
    // send/withdraw target the user's UUID (`profile.id`), not the handle.
    var heroConnectState = HeroConnectState.hidden;
    VoidCallback? onConnect;
    if (relation != null) {
      final receiverId =
          profile.id.isNotEmpty ? profile.id : (widget.userId ?? '');
      if (_connectBusy) {
        heroConnectState = HeroConnectState.busy;
      } else {
        switch (relation.kind) {
          case PublicConnectKind.self:
            heroConnectState = HeroConnectState.hidden;
          case PublicConnectKind.connected:
            heroConnectState = HeroConnectState.connected;
          case PublicConnectKind.outgoing:
            heroConnectState = HeroConnectState.requested;
            onConnect = () => _runConnect(receiverId, relation);
          case PublicConnectKind.incoming:
            heroConnectState = HeroConnectState.incoming;
            onConnect = () => _runConnect(receiverId, relation);
          case PublicConnectKind.none:
            heroConnectState = HeroConnectState.connect;
            onConnect = () => _runConnect(receiverId, relation);
        }
      }
    }

    // Real hero stats. Self "Connections" is derived from the accepted list (the
    // count endpoint is broken). We do NOT show a total Connections stat for
    // other users (no trustworthy source) — the mutual-connections proof row
    // below the hero carries the meaningful shared metric instead.
    final int? realCount =
        _isOtherUser ? null : ref.watch(selfConnectionCountProvider).value;
    final stats = widget.mode.isCv
        ? _cvStats(profile, realCount)
        : _realStats(profile, realCount);

    return Stack(
      children: [
        ProfileFoldingSections(
          child: RefreshIndicator(
            onRefresh: _refreshAll,
            edgeOffset: MediaQuery.of(context).padding.top,
            child: ListView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              padding: EdgeInsets.only(bottom: navSpace),
              // Build a screenful ahead in both directions, and keep every
              // row alive once built (below): scrolling back up must not tear
              // down and rebuild the hero — re-decoding its photos and
              // replaying its entrance — which is what made the return trip
              // stutter.
              scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
              children: [
                _KeepAlive(
                    child: ProfileHero(
                  mode: widget.mode,
                  data: data,
                  scrollOffset: _offset,
                  onBack: () => _back(context),
                  onShare: () => _share(context),
                  onCopyLink: () => _copyLink(context),
                  onEditProfile: () => context.push(RouteNames.profileEdit),
                  // The owner's "…" unfolds its menu in place: tap to open, tap
                  // again to close.
                  overflowItems: widget.mode.isSelf
                      ? [
                          HeroMenuItem(
                            icon: Icons.visibility_outlined,
                            label: 'Preview public profile',
                            onTap: () => openPublicProfile(context),
                          ),
                          HeroMenuItem(
                            icon: Icons.badge_outlined,
                            label: 'View as CV',
                            onTap: () => context.push(RouteNames.profileCv),
                          ),
                          HeroMenuItem(
                            icon: Icons.link,
                            label: 'Copy profile link',
                            onTap: () => _copyLink(context),
                          ),
                        ]
                      : null,
                  onEditAvatar: widget.mode.isSelf
                      ? () => openProfilePhotoSheet(context)
                      : null,
                  // Self → the owner's sheet. Someone else → Remove connection /
                  // Block / Report. The self-preview (public mode, no handle) gets
                  // neither: there is nobody there to act on — and nor does your own
                  // profile opened by handle (from your own post, say), where every
                  // row would be aimed at yourself.
                  onOverflow: widget.mode.isSelf
                      ? () => _showOverflow(context)
                      : _isOtherUser && !_isOwnProfile(profile, relation)
                          ? () => _showMemberMenu(context, profile, relation)
                          : null,
                  connectState: heroConnectState,
                  onConnect: onConnect,
                  // Direct 1:1 chat with **this** person, keyed on their auth UUID
                  // (`profile.id`) — the same id the connect/withdraw calls use, and
                  // never the public handle in `widget.userId`. Pushed, so Back
                  // returns to this profile.
                  messageState: messageAvailabilityFor(relation),
                  messageBlockedReason: relation == null
                      ? ''
                      : messageBlockedReasonFor(relation.kind),
                  onMessage: () => openDirectChat(
                    context,
                    profile.id,
                    personName: profile.name,
                  ),
                  onMessageBlocked: relation == null
                      ? null
                      : () => showSnackbar(
                            context,
                            messageBlockedReasonFor(relation.kind),
                          ),
                  statsOverride: stats,
                  // Self "Connections" is a tappable network metric → open My Network.
                  onConnectionsTap: widget.mode.isSelf
                      ? () => context.push(
                          '${RouteNames.networkConnections}?tab=connections')
                      : null,
                )),
                if (_isOtherUser) _MutualProof(handle: widget.userId!),
                const SizedBox(height: 12),
                // Owed Job Readiness Sprint entry point (self view only) — renders
                // nothing when no sprint is pending.
                if (widget.mode.isSelf) const SprintPendingCard(),
                for (final section
                    in _bodySections(context, ref, profile, data))
                  _KeepAlive(
                    child: ProfileReveal(
                        delay: const Duration(milliseconds: 120),
                        child: section),
                  ),
              ],
            ),
          ),
        ),
        _StickyBar(
          offset: _offset,
          name: data.name,
          avatarUrl: data.avatarUrl,
          onBack: () => _back(context),
          onShare: () => _share(context),
        ),
      ],
    );
  }

  /// Pull-to-refresh: reload the profile itself and drop every cached
  /// activity feed (both tabs re-fetch on next watch). The indicator settles
  /// on the profile reload; a failure renders as the screen's inline error
  /// state rather than throwing out of the gesture.
  Future<void> _refreshAll() async {
    _refreshProfile();
    ref.invalidate(activityFeedProvider);
    try {
      if (_isOtherUser) {
        await ref.read(publicProfileBundleProvider(widget.userId!).future);
      } else {
        await ref.read(myProfileProvider.future);
      }
    } catch (_) {
      // Surfaced by the AsyncValue error state; nothing extra to do here.
    }
  }

  /// Builds the hero stat row from real data only — Yrs Exp (derived from
  /// experiences), Connections (count API), and Profile Views (self only, from
  /// the session's impression count). Stats with no real value are omitted; the
  /// stats card hides itself entirely when the list is empty (no fake numbers).
  List<ProfileStat> _realStats(UserProfile profile, int? connectionCount) {
    final stats = <ProfileStat>[];
    final yrs = _yearsOfExperience(profile.experiences);
    if (yrs != null) stats.add(ProfileStat(yrs, 'Yrs Exp'));
    if (connectionCount != null) {
      stats.add(ProfileStat(compactCount(connectionCount), 'Connections'));
    }
    // Profile Views is a personal, self-only metric (impressionCount is only on
    // the session user, not on other users' public payloads).
    if (!_isOtherUser && profile.impressionCount > 0) {
      stats.add(
          ProfileStat(compactCount(profile.impressionCount), 'Profile Views'));
    }
    return stats;
  }

  /// Whole years since the earliest experience start date, as "N+" (or "<1").
  /// Null when the user has no dated experience → the stat is hidden.
  String? _yearsOfExperience(List<ProfileEntry> experiences) {
    DateTime? earliest;
    for (final e in experiences) {
      final s = e.startDate;
      if (s != null && (earliest == null || s.isBefore(earliest))) earliest = s;
    }
    if (earliest == null) return null;
    final years = DateTime.now().difference(earliest).inDays ~/ 365;
    return years <= 0 ? '<1' : '$years+';
  }

  /// CV/export hero stats derived entirely from real loaded data (replaces the
  /// mock 38+/12/500+). Each stat is omitted when there's no real value, so the
  /// export never shows a fake number.
  List<ProfileStat> _cvStats(UserProfile profile, int? connectionCount) {
    final stats = <ProfileStat>[];
    final yrs = _yearsOfExperience(profile.experiences);
    if (yrs != null) stats.add(ProfileStat(yrs, 'Years Exp'));
    if (profile.projects.isNotEmpty) {
      stats.add(ProfileStat('${profile.projects.length}', 'Projects'));
    }
    final skillCount = _skillCount(profile);
    if (skillCount > 0) stats.add(ProfileStat('$skillCount', 'Skills'));
    if (connectionCount != null) {
      stats.add(ProfileStat(compactCount(connectionCount), 'Network'));
    }
    return stats;
  }

  /// Count of distinct skills the user actually has (grouped skills, falling
  /// back to the key-skills list).
  int _skillCount(UserProfile profile) {
    final set = <String>{};
    for (final list in profile.categorizedSkills.values) {
      set.addAll(list);
    }
    if (set.isEmpty) set.addAll(profile.skills);
    return set.length;
  }

  List<Widget> _bodySections(BuildContext context, WidgetRef ref,
      UserProfile profile, ProfileViewData data) {
    final editable = widget.mode.isSelf;
    final canShowIntroVideo =
        profile.introMediaUrl != null && (editable || profile.introMediaPublic);
    return [
      // Social Links (Self) vs quick-contact pills (Public/CV).
      if (widget.mode.isSelf)
        SocialLinksCard(
          links: data.socialLinks,
          // Seed the editor from the real typed links, not the view chips.
          onEdit: () => openSocialLinksSheet(context, profile.links),
        )
      else
        ContactPillsRow(chips: data.socialLinks),
      ProfileBioCard(
        mode: widget.mode,
        bio: data.bio,
        // Bio has a real scalar write path — route to the Edit Profile form.
        onEdit: editable ? () => context.push(RouteNames.profileEdit) : null,
      ),
      ProfileIntroVideoCard(
        mode: widget.mode,
        hasIntroVideo: canShowIntroVideo,
        introVideoUrl: canShowIntroVideo ? profile.introMediaUrl : null,
        introVideoPublic: profile.introMediaPublic,
        introUploading: _introUploading,
        onUploadIntro: editable ? () => _uploadIntro(context, ref) : null,
        onToggleIntroPublic:
            editable ? (v) => _setIntroPublic(context, ref, v) : null,
        onRemoveIntro: editable ? () => _removeIntro(context, ref) : null,
      ),
      if (widget.mode.showsActivity) ...[
        // Live activity feed, keyed by the internal auth UUID (`profile.id`) —
        // never the public handle/route param, which the endpoint rejects.
        // Owner controls (delete / visibility) exist on the Self view only.
        ActivitySection(
          userUuid: profile.id,
          isOwner: widget.mode.isSelf,
        ),
        const SizedBox(height: 6),
      ],
      // ── Visitor visibility, mirroring the website's own mount-site gates ──
      //
      // `UserPublicView` wraps Experience / Education / Skills in
      // `{hasX && ...}` — an empty one is absent, not an empty card, because
      // "no education added yet" is a statement about a stranger that the
      // product does not make. Languages, Proof of Work and Certifications ARE
      // rendered empty on a visitor profile (their own components own that
      // copy), and References hides itself. The owner always sees every
      // section, empty state and all, because each one is a thing they can act
      // on.
      if (editable || data.experiences.isNotEmpty)
        ExperienceSectionCard(
          entries: data.experiences,
          editable: editable,
          // Edit-sheet seeds use the real profile lists (not the placeholder-
          // filled view model) so a save never round-trips mock data.
          onAdd: editable
              ? () => openExperienceSheet(context, profile.experiences)
              : null,
          onEdit: editable
              ? () => openExperienceSheet(context, profile.experiences)
              : null,
        ),
      if (editable || data.educations.isNotEmpty)
        EducationSectionCard(
          entries: data.educations,
          editable: editable,
          onAdd: editable
              ? () => openEducationSheet(context, profile.educations)
              : null,
          onEdit: editable
              ? () => openEducationSheet(context, profile.educations)
              : null,
        ),
      if (editable || data.categorizedSkills.isNotEmpty)
        SkillsSectionCard(
          categorized: data.categorizedSkills,
          categoryColors: profile.skillCategoryColors,
          editable: editable,
          onAdd: editable
              ? () => openSkillsSheet(context, profile.categorizedSkills,
                  profile.skillCategoryColors)
              : null,
          onEdit: editable
              ? () => openSkillsSheet(context, profile.categorizedSkills,
                  profile.skillCategoryColors)
              : null,
        ),
      // Technical Skills intentionally omitted: there is no backend source for
      // proficiency-bar data, so it was placeholder-only. Hidden to avoid
      // showing invented data as if the user entered it.
      LanguagesSectionCard(
        languages: data.languages,
        editable: editable,
        onAdd: editable
            ? () => openLanguagesSheet(context, profile.languages)
            : null,
        onEdit: editable
            ? () => openLanguagesSheet(context, profile.languages)
            : null,
      ),
      ProjectsSectionCard(
        projects: data.projects,
        editable: editable,
        onAdd: editable ? () => openProjectSheet(context) : null,
        onEditProject:
            editable ? (p) => openProjectSheet(context, project: p) : null,
      ),
      // References and Certifications load themselves rather than riding on
      // the profile payload — neither is part of `/work-details`. Both are
      // keyed by the internal auth UUID for the visitor read:
      // `certifications/public/{id}` matches the stored id verbatim and does
      // NOT resolve the `@handle` this screen is routed by.
      ReferencesSectionCard(
        editable: editable,
        userIdOrHandle: editable ? null : profile.id,
      ),
      CertificationsSectionCard(
        editable: editable,
        userUuid: editable ? null : profile.id,
      ),
    ];
  }

  void _back(BuildContext context) {
    if (_introUploading && !_leaveConfirmed) {
      _confirmLeaveWhileUploading();
      return;
    }
    _performBackNavigation(context);
  }

  void _performBackNavigation(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.home);
    }
  }

  Future<void> _confirmLeaveWhileUploading() async {
    if (!mounted) return;
    // The app's one confirmation dialog: Stay is the filled safe action,
    // Leave the named consequence.
    final leave = await showConfirmActionDialog(
      context,
      title: 'Leave while uploading?',
      message: 'Your intro video is still uploading. If you leave now, this '
          'screen will close before the upload finishes here.',
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
    );
    if (!leave || !mounted) return;

    if (context.canPop()) {
      setState(() => _leaveConfirmed = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
      return;
    }

    _performBackNavigation(context);
  }

  /// The canonical public profile link for the current view, built from the
  /// user's real handle (custom userId, e.g. `nitin-jiwnani-1`). Matches the web
  /// app's CV route (`/user/cv/{handle}`), constructed client-side. Returns null
  /// when no handle is available yet (link isn't shareable).
  String? _profileShareUrl() {
    final handle = _isOtherUser
        ? (widget.userId ?? '')
        : (AuthManager().currentUser?.userId ?? '');
    if (handle.isEmpty) return null;
    return ApiConstants.profileCvUrl(handle);
  }

  /// Share opens the OS share sheet with the profile link — except on the self
  /// profile (non-CV), where it first opens the in-app branded CV export preview
  /// so the user can see what they're sharing.
  void _share(BuildContext context) {
    if (widget.mode.isSelf && !widget.mode.isCv) {
      context.push(RouteNames.profileCv);
    } else {
      _shareLink(context);
    }
  }

  /// Opens the native share sheet with the canonical profile link.
  Future<void> _shareLink(BuildContext context) async {
    final url = _profileShareUrl();
    if (url == null) {
      _toast(context, "This profile link isn't available yet.");
      return;
    }
    // Share the canonical link as a real URI so targets that special-case URLs
    // (rich previews, link handling) keep working. share_plus disallows `text`
    // + `uri` together, so this stays link-only rather than adding intro copy.
    await SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
  }

  /// Copies the canonical public profile link to the clipboard.
  void _copyLink(BuildContext context) {
    final url = _profileShareUrl();
    if (url == null) {
      _toast(context, "This profile link isn't available yet.");
      return;
    }
    Clipboard.setData(ClipboardData(text: url));
    _toast(context, 'Profile link copied');
  }

  /// The Self View "…" overflow exposes the other two renderings so they're
  /// reachable in-app for preview.
  ///
  /// "Report profile" used to sit here behind `_isOtherUser` — but this sheet
  /// only ever opened from the self view's "…", so the row could never be
  /// reached. It lives in [_showMemberMenu] now.
  Future<void> _showOverflow(BuildContext context) async {
    final action = await showProfileActionSheet<_SelfOverflowAction>(
      context,
      actions: const [
        ProfileSheetAction(
          value: _SelfOverflowAction.previewPublic,
          icon: Icons.visibility_outlined,
          label: 'Preview public profile',
        ),
        ProfileSheetAction(
          value: _SelfOverflowAction.viewAsCv,
          icon: Icons.badge_outlined,
          label: 'View as CV',
        ),
        ProfileSheetAction(
          value: _SelfOverflowAction.copyLink,
          icon: Icons.link,
          label: 'Copy profile link',
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _SelfOverflowAction.previewPublic:
        openPublicProfile(context);
      case _SelfOverflowAction.viewAsCv:
        context.push(RouteNames.profileCv);
      case _SelfOverflowAction.copyLink:
        _copyLink(context);
    }
  }

  /// Whether a public-mode profile is actually the signed-in user's own.
  ///
  /// `connection/status` answers `isSelf` for it, but that call is non-fatal and
  /// degrades to "no relationship" when it fails — so the session's own ids are
  /// checked too (UUID and handle, as payloads disagree on which they carry).
  bool _isOwnProfile(UserProfile profile, PublicConnectState? relation) =>
      relation?.kind == PublicConnectKind.self ||
      isOwnAuthorForSession(
        authorId: profile.id,
        authorHandle: profile.userId,
      );

  /// The "…" on **someone else's** profile: Copy link, Remove connection (only
  /// for an accepted connection whose record id we hold), Block, Report.
  Future<void> _showMemberMenu(
    BuildContext context,
    UserProfile profile,
    PublicConnectState? relation,
  ) async {
    final connected =
        relation?.kind == PublicConnectKind.connected ? relation : null;
    final connectionId = connected?.connectionId ?? '';
    final action = await showProfileMemberMenu(
      context,
      name: profile.name,
      // Hidden while another relationship call is running: one in-flight
      // mutation per profile, the same rule the website's `connectionBusy`
      // applies to its own Remove.
      canRemoveConnection: connectionId.isNotEmpty && !_connectBusy,
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case ProfileMemberAction.copyLink:
        _copyLink(context);
      case ProfileMemberAction.removeConnection:
        if (connected != null) {
          await _removeConnection(context, profile, connected);
        }
      case ProfileMemberAction.block:
        await _blockMember(context, profile);
      case ProfileMemberAction.report:
        showReportContentSheet(
          context: context,
          targetType: ReportTargetType.profile,
          targetId: widget.userId!,
          targetLabel: 'this profile',
        );
    }
  }

  /// Confirms, then `DELETE /connection/:connectionId` — the accepted record's
  /// own id, which is what `connection/status` returns as `id` and what the
  /// website passes (`connectionStatusData.id`). The server also deletes any
  /// follow between the two, in both directions, which is why the dialog says
  /// so. Same wording as My Network → Connections.
  ///
  /// On success the hero goes back to **Connect** and Message back to its
  /// "connect first" state, exactly as `connection/status` would now report.
  /// On failure the hero keeps saying **Connected** — nothing was removed as
  /// far as this client knows — and the relationship is then re-read, because
  /// one failure (a 404) means the other person removed it first, and then
  /// "Connected" would be the thing that is wrong.
  Future<void> _removeConnection(
    BuildContext context,
    UserProfile profile,
    PublicConnectState connected,
  ) async {
    final connectionId = connected.connectionId;
    if (connectionId.isEmpty || _connectBusy) return;
    final name = profile.name.trim().isEmpty ? 'this member' : profile.name;
    // Taken up front: the refresh after the DELETE must still land if the
    // viewer leaves the profile while it is out, when `ref` is no longer usable.
    final container = ProviderScope.containerOf(context, listen: false);
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Remove connection?',
      message: 'You will no longer be connected with $name. '
          'This also removes any follow between you.',
      confirmLabel: 'Remove connection',
      cancelLabel: 'Stay connected',
    );
    if (!confirmed || !mounted || _connectBusy) return;

    setState(() => _connectBusy = true);
    try {
      await container
          .read(connectionRepositoryProvider)
          .removeConnection(connectionId);
      _connectOverride = const PublicConnectState(PublicConnectKind.none);
      // The accepted list shrank (and with it the derived self count); the
      // removed person can resurface as a suggestion; mutuals may have moved.
      container
        ..invalidate(acceptedConnectionsProvider)
        ..invalidate(peopleNetworkProvider)
        ..invalidate(profileSummaryProvider);
      if (_isOtherUser) {
        container.invalidate(publicMutualsProvider(widget.userId!));
      }
      if (context.mounted) showSnackbar(context, 'Connection removed');
    } catch (e) {
      // Keep showing exactly the relationship that was on screen — pinned, so
      // an older cached answer (say, the "Accept" this profile was opened on)
      // cannot resurface in its place — then ask the server what is true.
      _connectOverride = connected;
      if (mounted) {
        unawaited(_reconcileAfterFailedRemove(profile.id, connected));
      }
      if (context.mounted) {
        showSnackbar(
          context,
          e is RepositoryException ? e.message : 'Could not remove connection.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _connectBusy = false);
    }
  }

  /// After a failed remove, reads `connection/status` again and shows that —
  /// unless something else has changed the relationship on screen meanwhile.
  /// A failed read changes nothing: "Connected" stays, which is what the
  /// failed call left behind as far as anyone can tell.
  Future<void> _reconcileAfterFailedRemove(
    String peerUuid,
    PublicConnectState shown,
  ) async {
    if (peerUuid.isEmpty) return;
    final PublicConnectState fresh;
    try {
      fresh = await ref
          .read(connectionRepositoryProvider)
          .getConnectionState(peerUuid);
    } catch (_) {
      return;
    }
    if (!mounted || !identical(_connectOverride, shown)) return;
    setState(() => _connectOverride = fresh);
    if (fresh.kind != shown.kind) {
      // It really had gone (removed from the other side): the lists that
      // still show it are stale too.
      ref.invalidate(acceptedConnectionsProvider);
      ref.invalidate(peopleNetworkProvider);
      ref.invalidate(profileSummaryProvider);
    }
  }

  /// Blocks via the shared confirm dialog (one non-retrying toggle, truthful
  /// copy), then leaves: `auth-service` 404s a blocked pair's public profile
  /// from that moment, so staying would strand the viewer on a page whose next
  /// refresh is an error. Blocking does **not** remove an existing connection
  /// server-side — the dialog does not claim it does, and neither does this.
  ///
  /// Cancel, a failure, and the "they were already blocked, so that tap
  /// unblocked them" outcome all keep the profile open: in each the profile is
  /// still one this viewer may see. The dialog reports each of them itself.
  Future<void> _blockMember(BuildContext context, UserProfile profile) async {
    final blocked = await showBlockAuthorDialog(
      context: context,
      authorName: profile.name,
      // Block rows key on the auth UUID; the handle is only for cache keys.
      targetUserId: profile.id,
      profileHandle: widget.userId,
    );
    if (!blocked) return;

    // The dialog's shared block controller has already invalidated every
    // backend-filtered Network surface. Accepted connections and the chat
    // inbox are intentionally not refreshed: their queries do not filter
    // blocked users.
    if (context.mounted) _performBackNavigation(context);
  }

  void _toast(BuildContext context, String message) =>
      showSnackbar(context, message);

  // ── Intro media ──────────────────────────────────────────────────────────

  /// Picks a video and uploads it as the profile intro media, then refreshes.
  Future<void> _uploadIntro(BuildContext context, WidgetRef ref) async {
    if (_introUploading) return;
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final path = picked.path;
    final dot = path.lastIndexOf('.');
    final ext =
        (dot == -1 || dot == path.length - 1) ? 'mp4' : path.substring(dot + 1);
    final mime = ext.toLowerCase() == 'mov' ? 'video/quicktime' : 'video/mp4';
    setState(() {
      _introUploading = true;
      _leaveConfirmed = false;
    });
    try {
      await ref.read(resumeSectionsRepositoryProvider).uploadIntroMedia(
            filePath: path,
            mediaType: 'video',
            extension: ext.toLowerCase(),
            contentType: mime,
          );
      ref.invalidate(myProfileProvider);
      await ref.read(myProfileProvider.future);
      if (context.mounted) showSnackbar(context, 'Intro video uploaded');
    } catch (e) {
      if (context.mounted) showSnackbar(context, e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _introUploading = false;
          _leaveConfirmed = false;
        });
      }
    }
  }

  Future<void> _setIntroPublic(
      BuildContext context, WidgetRef ref, bool isPublic) async {
    try {
      await ref
          .read(resumeSectionsRepositoryProvider)
          .setIntroMediaVisibility(isPublic);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (context.mounted) showSnackbar(context, e.toString(), isError: true);
    }
  }

  Future<void> _removeIntro(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(resumeSectionsRepositoryProvider).deleteIntroMedia();
      ref.invalidate(myProfileProvider);
      if (context.mounted) showSnackbar(context, 'Intro video removed');
    } catch (e) {
      if (context.mounted) showSnackbar(context, e.toString(), isError: true);
    }
  }
}

/// The rows of the owner's "…" sheet.
enum _SelfOverflowAction { previewPublic, viewAsCv, copyLink }

/// Honest mutual-connection proof on another user's public profile:
/// "N mutual connections" with a small overlapping avatar sample. Renders
/// nothing while loading, on error, or when there are no mutuals (the endpoint
/// is non-fatal in the repository).
///
/// Drawn on the page under the hero's numbers rather than in a card of its
/// own: it is one more line about this person, and a full-width box for one
/// sentence was a large part of why the profile read as a stack of outlines.
///
/// NOT tappable by design: `GET /connection/mutuals/{userId}` returns only
/// `name` + `profilePic` for each sample user (no handle/UUID), so there is no
/// honest way to open an individual mutual person's profile yet. Make the avatars
/// tappable only once the backend includes a `userId`/handle in that payload.
class _MutualProof extends ConsumerWidget {
  const _MutualProof({required this.handle});

  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final mutuals = ref.watch(publicMutualsProvider(handle)).value;
    if (mutuals == null || mutuals.isEmpty) return const SizedBox.shrink();

    final sample = mutuals.sample.take(3).toList();
    final label = mutuals.count == 1
        ? '1 mutual connection'
        : '${mutuals.count} mutual connections';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (sample.isNotEmpty)
            _MutualAvatarStack(people: sample)
          else
            Icon(Icons.group_outlined,
                size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of up to three overlapping circular avatars (mutual-connection proof).
class _MutualAvatarStack extends StatelessWidget {
  const _MutualAvatarStack({required this.people});

  final List<MutualPerson> people;

  static const double _size = 26;
  static const double _overlap = 9;

  @override
  Widget build(BuildContext context) {
    final t = ProfileSurfaceTokens.of(context);
    return SizedBox(
      height: _size,
      width: _size + (people.length - 1) * (_size - _overlap),
      child: Stack(
        children: [
          for (int i = 0; i < people.length; i++)
            Positioned(
              left: i * (_size - _overlap),
              child: Container(
                padding: const EdgeInsets.all(1.5),
                // The canvas-coloured ring the hero avatar wears, so the
                // overlapping discs separate the same way.
                decoration:
                    BoxDecoration(color: t.avatarRing, shape: BoxShape.circle),
                child: _MutualAvatar(person: people[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _MutualAvatar extends StatelessWidget {
  const _MutualAvatar({required this.person});

  final MutualPerson person;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final url = sanitizeAvatarUrl(person.avatarUrl);
    final provider = cachedImageProvider(url);
    return CircleAvatar(
      radius: _MutualAvatarStack._size / 2,
      backgroundColor: tokens.iconTile,
      backgroundImage: provider,
      child: provider == null
          ? Text(
              _initial(person.name),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.iconInk,
              ),
            )
          : null,
    );
  }

  static String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }
}

/// Shown when [myProfileProvider] fails (e.g. expired session, no network).
class _ProfileErrorView extends StatelessWidget {
  const _ProfileErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final colors = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: tokens.textTertiary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 20),
            AppButton.primary(
                label: 'Retry', onPressed: onRetry, expand: false),
          ],
        ),
      ),
    );
  }
}

/// The compact bar that slides down once the hero has scrolled away: back,
/// the person's avatar and name, share — on frosted black.
class _StickyBar extends StatelessWidget {
  const _StickyBar({
    required this.offset,
    required this.name,
    required this.avatarUrl,
    required this.onBack,
    required this.onShare,
  });

  final ValueListenable<double> offset;
  final String name;
  final String avatarUrl;
  final VoidCallback onBack;
  final VoidCallback onShare;

  /// Scroll distance over which the bar arrives.
  static const double _start = 220;
  static const double _span = 70;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final top = MediaQuery.of(context).padding.top;
    return ValueListenableBuilder<double>(
      valueListenable: offset,
      builder: (context, y, _) {
        final t = ((y - _start) / _span).clamp(0.0, 1.0);
        // Fully shown: no Opacity layer at all (opacity 1 still costs a
        // layer on the web renderer).
        if (t == 0) return const SizedBox.shrink();
        final eased = Curves.easeOutCubic.transform(t);
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Transform.translate(
            offset: Offset(0, -(1 - eased) * 24),
            child: _maybeFade(
              eased,
              // Solid, not frosted: a backdrop blur re-renders everything
              // behind the bar on every scroll frame, and on mobile Safari
              // that alone drops frames.
              RepaintBoundary(
                child: Container(
                  padding: EdgeInsets.fromLTRB(8, top + 6, 8, 8),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.96),
                    border: Border(
                      bottom: BorderSide(
                          color: colors.onSurface.withValues(alpha: 0.08)),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Back',
                      ),
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: colors.onSurface,
                        backgroundImage:
                            cachedImageProvider(sanitizeAvatarUrl(avatarUrl)),
                        child: avatarUrl.isEmpty
                            ? Text(
                                name.isEmpty ? '?' : name[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: colors.surface,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onShare,
                        icon: const Icon(Icons.ios_share, size: 20),
                        tooltip: 'Share',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _maybeFade(double t, Widget child) =>
      t >= 1 ? child : Opacity(opacity: t, child: child);
}

/// Keeps a list row alive once built, so scrolling away and back does not
/// rebuild it (and replay its entrance animation).
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The loading state: the hero's and first sections' silhouettes, shimmering.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    Widget box(double w, double h, {double r = 8}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(r),
          ),
        );
    return ProfileShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, top + 120, 20, 0),
        children: [
          Align(alignment: Alignment.centerLeft, child: box(104, 104, r: 52)),
          const SizedBox(height: 20),
          Align(alignment: Alignment.centerLeft, child: box(220, 30)),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: box(160, 16)),
          const SizedBox(height: 18),
          Row(children: [
            box(110, 30, r: 15),
            const SizedBox(width: 8),
            box(130, 30, r: 15)
          ]),
          const SizedBox(height: 22),
          box(double.infinity, 76, r: 16),
          const SizedBox(height: 16),
          box(double.infinity, 40, r: 12),
          const SizedBox(height: 36),
          for (var i = 0; i < 3; i++) ...[
            box(120, 14),
            const SizedBox(height: 14),
            box(double.infinity, 64, r: 12),
            const SizedBox(height: 30),
          ],
        ],
      ),
    );
  }
}
