import 'dart:math' as math;

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/helpers/work_link_url.dart';
import '../../../core/helpers/avatar_url.dart';
import '../../../core/helpers/relative_time.dart';
import '../../../core/helpers/snackbar_helper.dart';
import '../../../core/theme/color_schemes.dart';
import '../../../core/theme/glass_tokens.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../shared/screens/in_app_browser_screen.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/confirm_action_dialog.dart';
import '../../../shared/widgets/glass/glass.dart';
// `show Activity` only: post_models also exports a `Visibility` enum that
// would collide with Flutter's `Visibility` widget.
import '../../post/data/models/post_models.dart' show Activity;
import '../data/activity_presentation.dart';
import '../data/models/user_profile.dart';
import '../data/profile_view_data.dart';
import '../../../core/router/route_names.dart';
import '../providers/activity_provider.dart';
import 'profile_activity_tabs.dart';
import 'profile_posts_list.dart';
import '../screens/intro_video_player_screen.dart';
import 'profile_detail_widgets.dart';
import 'profile_entry_cards.dart';
import 'profile_motion.dart';
import 'profile_misc_widgets.dart';
import 'profile_section.dart';
import 'profile_sheet_kit.dart' show ProfileSheetAction, showProfileActionSheet;
import 'profile_surface.dart';
import '../../../core/extensions/context_extensions.dart';

// ── Social links ─────────────────────────────────────────────────────────────

/// Opens a profile's social link in the in-app browser.
///
/// Profile links are user-supplied, so the scheme is checked before anything is
/// loaded — the browser screen re-checks too, but failing here means a bad link
/// shows a message instead of pushing an empty screen. Some resume-parsed links
/// arrive without a scheme ("github.com/x"), which would otherwise be rejected
/// outright, so a bare host is promoted to https rather than dropped.
void openProfileLink(BuildContext context, WorkLink link) {
  final raw = link.href.trim();
  if (raw.isEmpty) return;
  final normalized = raw.startsWith('http://') || raw.startsWith('https://')
      ? raw
      : 'https://$raw';
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasAuthority) {
    showSnackbar(context, 'That link doesn\'t look valid.', isError: true);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => InAppBrowserScreen(
        url: normalized,
        title: link.label,
      ),
    ),
  );
}

/// Brand marks darker than this are treated as **monochrome** marks (GitHub,
/// X, Medium, CodePen, Dev.to, Notion — all near-black on the web) and inked
/// in the theme's own high-emphasis text colour rather than lifted toward a
/// grey that would read as disabled. Everything brighter keeps its brand hue.
const double kMonochromeBrandLuminance = 0.05;

/// How a platform's mark is inked on a social-link chip: the glyph colour and
/// the faint tint behind it.
///
/// The chip itself is neutral charcoal glass — the *whole* chip used to be a
/// brand-tinted pill, which put a navy, an orange and a purple block side by
/// side and left the LinkedIn label as blue-on-dark-blue. The brand now lives
/// in exactly two places: the glyph, at full brand colour (lifted only as far
/// as 3:1 against the chip face demands, hue preserved), and a low-alpha
/// backing behind it. The label is always near-white, so the platform is
/// named in text as well as in colour.
/// The profile's one burst of colour: a single electric neon for every link
/// chip's label (the chip itself stays neutral), so the links read as one set
/// against the black-and-white page. Change it here to recolour them
/// all.
const Color kProfileLinkNeon = Color(0xFF2D9CFF);

/// Every platform gets the same neon; the glyph shape and label say which.
Color profileNeonFor(WorkLinkKind kind) => kProfileLinkNeon;

/// The resume chip matches the links.
const Color kProfileResumeNeon = kProfileLinkNeon;

({Color glyph, Color tile}) socialLinkAccent(
  BuildContext context,
  WorkLink link,
) {
  final colors = context.colorScheme;
  final t = ProfileSurfaceTokens.of(context);
  final brand = link.color;
  if (Theme.of(context).colorScheme == SyncUpColorSchemes.mono) {
    // Neutral glyph tile; the neon is carried by the label alone.
    return (
      glyph: colors.onSurface,
      tile: colors.onSurface.withValues(alpha: 0.10),
    );
  }
  if (brand.computeLuminance() < kMonochromeBrandLuminance) {
    return (
      glyph: colors.onSurface,
      tile: colors.onSurface.withValues(alpha: 0.10),
    );
  }
  // A faint wash of the brand, not a block. The glyph is then lifted against
  // what it is actually drawn on — that wash over the chip face — so it holds
  // 3:1 on its own tile, not just on the bare chip.
  final tile = brand.withValues(alpha: 0.12);
  final glyph =
      readableBrandColor(brand, Color.alphaBlend(tile, t.chipSurface));
  return (glyph: glyph, tile: tile);
}

/// One social / portfolio link as a compact glass chip: a brand-inked glyph on
/// a faint brand tile, the platform (or domain) as near-white text, on the
/// profile's neutral chip pane.
///
/// Sized for a `Wrap`: the label ellipsises inside [maxWidth], so a long
/// custom domain never pushes past the card edge, and the chip is 36pt tall
/// inside a 44pt tap target. The full destination survives as the tooltip and
/// in the semantics announcement, so nothing is lost to the ellipsis.
class SocialLinkChip extends StatelessWidget {
  const SocialLinkChip({
    super.key,
    required this.link,
    this.onTap,
    this.maxWidth = defaultMaxWidth,
    this.expand = false,
  });

  final WorkLink link;
  final VoidCallback? onTap;

  /// Fill the width it is given (a grid cell) instead of hugging its label.
  final bool expand;

  /// The widest a chip may grow before its label ellipsises.
  final double maxWidth;

  static const double defaultMaxWidth = 240;

  /// The visual height; the tap target adds 4pt above and below.
  static const double height = 36;

  /// What a screen reader hears: platform (or "Website") and where it goes.
  String get announcement {
    final where = link.domain.isEmpty ? link.href : link.domain;
    return link.isRecognisedPlatform
        ? '${link.label}. Opens $where'
        : 'Website. Opens $where';
  }

  @override
  Widget build(BuildContext context) {
    final accent = socialLinkAccent(context, link);
    return Tooltip(
      message: link.href,
      child: ProfileChipFace(
        glyph: workLinkGlyph(link.kind, size: 13, color: accent.glyph),
        glyphTile: accent.tile,
        neonLabel: Theme.of(context).colorScheme == SyncUpColorSchemes.mono
            ? profileNeonFor(link.kind)
            : null,
        label: link.label,
        semanticLabel: announcement,
        onTap: onTap,
        expand: expand,
        maxWidth: maxWidth,
      ),
    );
  }
}

/// The face every link chip shares: a glyph tile, a label, on the profile's
/// chip pane, inside a 44pt target. [expand] fills a grid cell.
class ProfileChipFace extends StatelessWidget {
  const ProfileChipFace({
    super.key,
    required this.glyph,
    required this.glyphTile,
    required this.label,
    required this.semanticLabel,
    this.onTap,
    this.expand = false,
    this.maxWidth = SocialLinkChip.defaultMaxWidth,
    this.busy = false,
    this.neonLabel,
  });

  /// When set, the label is drawn in this neon with a glow — the chip itself
  /// stays neutral.
  final Color? neonLabel;

  final Widget glyph;
  final Color glyphTile;
  final String label;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool expand;
  final double maxWidth;

  /// Swaps the glyph for a small spinner (an open in flight).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final t = ProfileSurfaceTokens.of(context);
    final radius = BorderRadius.circular(ProfileSurfaceTokens.chipRadius);
    final chip = GlassPressable(
      onPressed: onTap,
      borderRadius: radius,
      pressedScale: 0.96,
      builder: (context, s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GlassSurface(
          spec: GlassSpec.lerp(
              t.chip, t.chipPressed, math.max(s.press, s.hover * 0.5)),
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: SocialLinkChip.height),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: glyphTile,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: busy
                        ? SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: colors.onSurface,
                            ),
                          )
                        : glyph,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: neonLabel ?? colors.onSurface,
                        fontSize: 12.5,
                        fontWeight: neonLabel != null
                            ? FontWeight.w700
                            : FontWeight.w600,
                        letterSpacing: 0.05,
                        // Electrified: a tight bright halo plus a wider
                        // soft one, like a neon tube.
                        shadows: neonLabel == null
                            ? null
                            : [
                                Shadow(
                                  color: neonLabel!.withValues(alpha: 0.9),
                                  blurRadius: 4,
                                ),
                                Shadow(
                                  color: neonLabel!.withValues(alpha: 0.55),
                                  blurRadius: 12,
                                ),
                              ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: expand
          ? chip
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.textScalerOf(context).scale(maxWidth),
              ),
              child: chip,
            ),
    );
  }
}

/// The links as bare platform marks: one round glyph per link, no label. The
/// platform is still named in the tooltip and the screen-reader announcement.
class _LinkChips extends StatelessWidget {
  const _LinkChips({required this.links});

  final List<WorkLink> links;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final l in links)
          SocialLinkIcon(link: l, onTap: () => openProfileLink(context, l)),
      ],
    );
  }
}

/// One social / portfolio link as just its logo, on a round glass disc.
class SocialLinkIcon extends StatelessWidget {
  const SocialLinkIcon({super.key, required this.link, this.onTap});

  final WorkLink link;
  final VoidCallback? onTap;

  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    final t = ProfileSurfaceTokens.of(context);
    final ink = context.colorScheme.onSurface;
    final radius = BorderRadius.circular(size / 2);
    final where = link.domain.isEmpty ? link.href : link.domain;
    return Tooltip(
      message: link.isRecognisedPlatform ? link.label : where,
      child: Semantics(
        button: true,
        label: link.isRecognisedPlatform
            ? '${link.label}. Opens $where'
            : 'Website. Opens $where',
        excludeSemantics: true,
        child: GlassPressable(
          onPressed: onTap,
          borderRadius: radius,
          pressedScale: 0.92,
          builder: (context, s) => SizedBox.square(
            dimension: size,
            child: GlassSurface(
              spec: GlassSpec.lerp(
                  t.chip, t.chipPressed, math.max(s.press, s.hover * 0.5)),
              borderRadius: radius,
              child: Center(
                child: workLinkGlyph(link.kind, size: 19, color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Editable "Social Links" management card — Self View only. Renders the real
/// typed links; empty prompts the user to add some via the edit affordance.
class SocialLinksCard extends StatelessWidget {
  const SocialLinksCard({
    super.key,
    required this.links,
    this.onEdit,
  });

  final List<WorkLink> links;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.link,
            title: 'Social Links',
            showEdit: true,
            onEdit: onEdit,
          ),
          const SizedBox(height: 10),
          if (links.isEmpty)
            GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Add links so people can find you elsewhere.',
                  style: TextStyle(fontSize: 13, color: tokens.textTertiary),
                ),
              ),
            )
          else
            _LinkChips(links: links),
        ],
      ),
    );
  }
}

/// The visitor's (and the CV's) view of the same links: the same card and the
/// same chips as the owner's, minus the edit control. Renders nothing when
/// there are no links — a stranger's empty section is not a statement the
/// product makes.
class ContactPillsRow extends StatelessWidget {
  const ContactPillsRow({super.key, required this.chips});

  final List<WorkLink> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(icon: Icons.link, title: 'Links'),
          const SizedBox(height: 10),
          _LinkChips(links: chips),
        ],
      ),
    );
  }
}

// ── Bio ──────────────────────────────────────────────────────────────────────

/// Bio card: the user's own words, nothing else. The intro video is its own
/// section ([ProfileIntroVideoCard]).
class ProfileBioCard extends StatelessWidget {
  const ProfileBioCard({
    super.key,
    required this.mode,
    required this.bio,
    this.onEdit,
  });

  final ProfileViewMode mode;
  final String bio;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.person_outline,
            title: 'Bio',
            showEdit: mode.isSelf,
            onEdit: onEdit,
          ),
          const SizedBox(height: 10),
          // Honest empty state — a profile without a saved bio never shows
          // placeholder copy as if the user wrote it.
          if (bio.trim().isEmpty)
            Text(
              'No bio added yet.',
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: tokens.textTertiary,
              ),
            )
          else
            Text(
              bio,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: colors.onSurface,
              ),
            ),
        ],
      ),
    );
  }
}

/// Intro video section. Self View shows an upload zone (or, once uploaded, the
/// thumbnail + a "Make video public" toggle + Remove); Public/CV show the
/// thumbnail only when an intro video exists, and nothing otherwise.
class ProfileIntroVideoCard extends StatelessWidget {
  const ProfileIntroVideoCard({
    super.key,
    required this.mode,
    this.hasIntroVideo = false,
    this.introVideoUrl,
    this.introVideoPublic = false,
    this.introUploading = false,
    this.onUploadIntro,
    this.onToggleIntroPublic,
    this.onRemoveIntro,
  });

  final ProfileViewMode mode;
  final bool hasIntroVideo;
  final String? introVideoUrl;
  final bool introVideoPublic;
  final bool introUploading;
  final VoidCallback? onUploadIntro;
  final ValueChanged<bool>? onToggleIntroPublic;
  final VoidCallback? onRemoveIntro;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final hasVideo = hasIntroVideo && introVideoUrl != null;
    if (!mode.isSelf && !hasVideo) return const SizedBox.shrink();
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.play_circle_outline,
            title: 'Intro Video',
          ),
          const SizedBox(height: 10),
          if (!mode.isSelf)
            _BioVideoThumbnail(videoUrl: introVideoUrl!)
          else if (introUploading)
            const _IntroVideoUploadZone(busy: true)
          else if (hasVideo) ...[
            _BioVideoThumbnail(videoUrl: introVideoUrl!),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Make video public',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: introVideoPublic,
                  onChanged: onToggleIntroPublic,
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton.text(
                label: 'Remove intro video',
                leading: Icons.delete_outline,
                destructive: true,
                onPressed: onRemoveIntro,
              ),
            ),
          ] else
            _IntroVideoUploadZone(onUpload: onUploadIntro),
        ],
      ),
    );
  }
}

class _IntroVideoUploadZone extends StatelessWidget {
  const _IntroVideoUploadZone({this.onUpload, this.busy = false});

  final VoidCallback? onUpload;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    // The shared drop-zone treatment (see `ProjectTile`, `_ResumeEmptyZone`).
    return DottedBorder(
      borderType: BorderType.RRect,
      radius: const Radius.circular(12),
      color: tokens.uploadZoneBorder,
      strokeWidth: 1.5,
      dashPattern: const [6, 4],
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: tokens.uploadZoneFill,
        ),
        child: Column(
          children: [
            Text(
              'Add an intro video',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Introduce yourself and stand out from other profiles.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: tokens.textTertiary),
            ),
            const SizedBox(height: 14),
            AppButton.secondary(
              label: busy ? 'Uploading…' : 'Upload video',
              leading: Icons.upload_outlined,
              loading: busy,
              onPressed: onUpload,
              expand: false,
              size: AppButtonSize.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// Intro-video card: shows the video's real first frame as a poster (so it
/// isn't just a flat colour), with a play overlay; tapping opens the full
/// player. Falls back to a gradient placeholder if the poster can't load.
class _BioVideoThumbnail extends StatefulWidget {
  const _BioVideoThumbnail({required this.videoUrl});

  final String videoUrl;

  @override
  State<_BioVideoThumbnail> createState() => _BioVideoThumbnailState();
}

class _BioVideoThumbnailState extends State<_BioVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadPoster();
  }

  @override
  void didUpdateWidget(_BioVideoThumbnail old) {
    super.didUpdateWidget(old);
    if (old.videoUrl != widget.videoUrl) {
      _controller?.dispose();
      _controller = null;
      _ready = false;
      _loadPoster();
    }
  }

  Future<void> _loadPoster() async {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null || !uri.hasScheme) return;
    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.seekTo(Duration.zero);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      // A private/undecodable URL just falls back to the gradient placeholder.
      debugPrint('Intro video poster failed: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final controller = _controller;
    final showPoster = _ready && controller != null;
    return Semantics(
      button: true,
      label: 'Play intro video',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => IntroVideoPlayerScreen(videoUrl: widget.videoUrl),
          ),
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (showPoster)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  )
                else
                  // The same tonal panel a coverless project gets: graphite,
                  // not the indigo hero slab that used to sit here.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.surfaceContainerHigh,
                          colors.surfaceContainerHighest,
                        ],
                      ),
                    ),
                  ),
                // Darken slightly so the play button reads over any frame.
                if (showPoster)
                  DecoratedBox(
                    decoration: BoxDecoration(
                        color: colors.shadow.withValues(alpha: 0.13)),
                  ),
                const Center(child: _PlayButton()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final glass = GlassTokens.of(context);
    // The kit's charcoal disc over the poster frame — it reads on a bright
    // frame (the fill) and on a dark one (the rim).
    return SizedBox.square(
      dimension: 48,
      child: GlassSurface(
        spec: glass.secondary,
        borderRadius: BorderRadius.circular(24),
        child: Center(
          child:
              Icon(Icons.play_arrow_rounded, size: 28, color: colors.onSurface),
        ),
      ),
    );
  }
}

// ── Activity ─────────────────────────────────────────────────────────────────

/// "Activity" label + Posts/Activities tabs over the LIVE activity feed
/// (`GET /post-service/activity/user/{uuid}`). Self + Public only — never CV.
///
/// [userUuid] is the profile's internal auth **UUID** ([UserProfile.id]); the
/// endpoint rejects public handles. [isOwner] is true only on the Self view:
/// it gates the per-row visibility chip and the overflow menu (delete /
/// visibility). Rows are event summaries built strictly from fields the
/// backend supplies — no invented like counts, media, or post bodies.
class ActivitySection extends ConsumerStatefulWidget {
  const ActivitySection({
    super.key,
    required this.userUuid,
    required this.isOwner,
  });

  final String userUuid;
  final bool isOwner;

  @override
  ConsumerState<ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends ConsumerState<ActivitySection> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    // No UUID (e.g. a public payload missing `id`) → nothing to query; render
    // no section rather than a guaranteed-failing feed.
    if (widget.userUuid.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same heading language as every other section: a drawn hairline,
        // then a glyph and a tracked uppercase title.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ProfileDrawnLine(
            color: colors.onSurface.withValues(alpha: 0.28),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SectionHeader(title: 'Activity'),
        ),
        const SizedBox(height: 4),
        ProfileActivityTabs(
          selected: _tab,
          onSelected: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 12),
        // Two tabs, two endpoints, two providers — never one filtered feed.
        //
        // Posts are authored posts (`/post/get-all/{uuid}`), the same source
        // the website's PostsSection reads. Activities are recorded activity
        // *events* (`/activity/user/{uuid}`), unfiltered. Each subtree is
        // keyed so switching tabs can't carry rows, spinners, errors or page
        // cursors across.
        if (_tab == 0)
          // A bounded horizontal glance, not a nested vertical feed — the
          // profile already scrolls through eight sections, and a second feed
          // inside it has no natural end. "View all posts" is where the real
          // feed lives.
          ProfilePostsPreview(
            key: ValueKey('profile-posts-preview-${widget.userUuid}'),
            userUuid: widget.userUuid,
            emptyLabel: 'No posts yet.',
            onViewAll: () => context.push(
              '${RouteNames.profileAllPosts}?userId=${widget.userUuid}'
              '&owner=${widget.isOwner}&tab=posts',
            ),
          )
        else
          // Capped at three with a "View all activity" action, for the same
          // reason the Posts tab is a carousel: the profile is a glance, and a
          // paginating feed nested in it has no natural end.
          ProfileActivityFeedList(
            key: ValueKey('profile-activities-${widget.userUuid}'),
            userUuid: widget.userUuid,
            isOwner: widget.isOwner,
            emptyLabel: 'No recent activity yet.',
            preview: true,
            onViewAll: () => context.push(
              '${RouteNames.profileAllPosts}?userId=${widget.userUuid}'
              '&owner=${widget.isOwner}&tab=activities',
            ),
          ),
      ],
    );
  }
}

/// One tab's feed body: initial spinner / full error + Retry / honest empty
/// copy / event rows with a load-more footer. Pagination failures keep the
/// already-loaded rows and offer an inline retry.
class ProfileActivityFeedList extends ConsumerWidget {
  const ProfileActivityFeedList({
    super.key,
    required this.userUuid,
    required this.isOwner,
    required this.emptyLabel,
    this.preview = false,
    this.onViewAll,
  });

  final String userUuid;
  final bool isOwner;
  final String emptyLabel;

  /// Preview mode caps the list at [kActivityPreviewLimit], drops the
  /// "Load more" footer, and offers [onViewAll] instead — the profile page is
  /// a glance, and a second paginating feed inside it has no natural end.
  final bool preview;

  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokensOrDefault;
    final key =
        preview ? activityPreviewKey(userUuid) : activityFullFeedKey(userUuid);
    final state = ref.watch(activityFeedProvider(key));
    final notifier = ref.read(activityFeedProvider(key).notifier);

    if (state.isInitialLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (state.initialError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          children: [
            Text(
              state.initialError!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: tokens.textTertiary),
            ),
            const SizedBox(height: 10),
            AppButton.secondary(
              label: 'Retry',
              onPressed: notifier.retry,
              expand: false,
              size: AppButtonSize.compact,
            ),
          ],
        ),
      );
    }

    // Visitor-facing surfaces only ever show PUBLIC rows. The server already
    // enforces this for real visitors; this also keeps the owner's own
    // "preview public profile" honest about what others actually see.
    final visible = isOwner
        ? state.activities
        : [
            for (final a in state.activities)
              if (activityIsPublic(a)) a,
          ];
    // Capped on display as well as on request: the server is not obliged to
    // honour the limit it was asked for.
    final rows =
        preview ? visible.take(kActivityPreviewLimit).toList() : visible;

    if (rows.isEmpty) {
      // Nothing visible yet, but later pages may still hold visible rows (a
      // visitor's page 1 can be entirely PRIVATE): keep paginating
      // automatically until something shows up, pagination is exhausted, or a
      // page fails. The fetch is kicked post-frame — never during build — and
      // loadMore's own in-flight guard collapses duplicate schedules.
      // Preview mode opts out: it is capped at three rows, so paging on in
      // search of a visible one would defeat the cap.
      if (!preview &&
          (state.isLoadingMore ||
              (state.hasMore && state.loadMoreError == null))) {
        if (!state.isLoadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ref
                  .read(activityFeedProvider(preview
                          ? activityPreviewKey(userUuid)
                          : activityFullFeedKey(userUuid))
                      .notifier)
                  .loadMore();
            }
          });
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (state.loadMoreError != null) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            children: [
              Text(
                state.loadMoreError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: tokens.textTertiary),
              ),
              const SizedBox(height: 10),
              AppButton.secondary(
                label: 'Retry',
                onPressed: notifier.loadMore,
                expand: false,
                size: AppButtonSize.compact,
              ),
            ],
          ),
        );
      }
      // Truly exhausted with nothing visible → the honest empty state.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Text(
          emptyLabel,
          style: TextStyle(fontSize: 13.5, color: tokens.textTertiary),
        ),
      );
    }

    return Column(
      children: [
        for (final activity in rows)
          ProfileActivityRow(
            activity: activity,
            isOwner: isOwner,
            pending: state.pendingIds.contains(activity.id),
            onMenu: isOwner && !state.pendingIds.contains(activity.id)
                ? () => _showOwnerMenu(context, ref, activity)
                : null,
          ),
        if (!preview && state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (state.loadMoreError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Text(
                  state.loadMoreError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: tokens.textTertiary),
                ),
                AppButton.text(label: 'Retry', onPressed: notifier.loadMore),
              ],
            ),
          )
        else if (preview && onViewAll != null)
          ViewAllButton(label: 'View all activity', onTap: onViewAll!)
        else if (!preview && state.hasMore)
          AppButton.text(label: 'Load more', onPressed: notifier.loadMore),
        const SizedBox(height: 4),
      ],
    );
  }

  // ── Owner controls ────────────────────────────────────────────────────────

  Future<void> _showOwnerMenu(
    BuildContext context,
    WidgetRef ref,
    Activity activity,
  ) async {
    final isPublic = activityIsPublic(activity);
    final action = await showProfileActionSheet<_OwnerMenuAction>(
      context,
      actions: [
        ProfileSheetAction(
          value: _OwnerMenuAction.toggleVisibility,
          icon: isPublic ? Icons.lock_outline : Icons.public,
          label: isPublic ? 'Make private' : 'Make public',
        ),
        const ProfileSheetAction(
          value: _OwnerMenuAction.delete,
          icon: Icons.delete_outline,
          label: 'Delete activity',
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _OwnerMenuAction.toggleVisibility:
        await _setVisibility(
            context, ref, activity, isPublic ? 'PRIVATE' : 'PUBLIC');
      case _OwnerMenuAction.delete:
        await _confirmDelete(context, ref, activity);
    }
  }

  Future<void> _setVisibility(
    BuildContext context,
    WidgetRef ref,
    Activity activity,
    String visibility,
  ) async {
    // The notifier owns the optimistic patch + rollback — completing it never
    // depends on this widget staying mounted.
    final error = await ref
        .read(activityFeedProvider(preview
                ? activityPreviewKey(userUuid)
                : activityFullFeedKey(userUuid))
            .notifier)
        .setVisibility(activity.id, visibility);
    if (!context.mounted || error == null) return;
    showSnackbar(context, error, isError: true);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Activity activity,
  ) async {
    // The app's one confirmation dialog: the safe choice is the filled CTA,
    // the destructive one names its consequence.
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Delete activity?',
      message: "This removes it from your profile. This can't be undone.",
      confirmLabel: 'Delete activity',
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    final error = await ref
        .read(activityFeedProvider(preview
                ? activityPreviewKey(userUuid)
                : activityFullFeedKey(userUuid))
            .notifier)
        .deleteActivity(activity.id);
    if (!context.mounted) return;
    showSnackbar(
      context,
      error ?? 'Activity deleted',
      isError: error != null,
    );
  }
}

/// What the owner can do to one activity row from its "…".
enum _OwnerMenuAction { toggleVisibility, delete }

/// One activity event row: avatar · "Name action" · target/description ·
/// relative time, plus (owner only) a visibility chip and overflow menu.
/// Not tappable: no verified in-app destination exists yet for the activity
/// target types (no post-detail route; the job detail needs a `JobSummary`
/// the activity payload doesn't carry).
class ProfileActivityRow extends StatelessWidget {
  const ProfileActivityRow({
    super.key,
    required this.activity,
    required this.isOwner,
    this.pending = false,
    this.onMenu,
  });

  final Activity activity;
  final bool isOwner;

  /// A delete/visibility request is in flight for this row → the menu shows a
  /// small spinner and taps are ignored until it settles.
  final bool pending;

  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final action = activityActionLabel(activity);
    final target = activityTargetLabel(activity);
    final description = activityDescriptionLabel(activity);
    final name = activity.user.name.trim();
    final title = activity.user.userTitle?.trim() ?? '';
    final time = relativeTimeFromIso(activity.createdAt);

    // The section card pane at row scale. It appears on two grounds — the
    // profile and the All Activity screen — and both are the canvas now, so
    // one pane serves both.
    return ProfileSurface(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(12),
      radius: ProfileSurfaceTokens.nestedRadius,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppUserAvatar(
            name: name,
            avatarUrl: sanitizeAvatarUrl(activity.user.profilePic),
            size: 40,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One trailing header row: date and (owner-only) menu sit
                // together, vertically centered with each other.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: name.isEmpty ? 'A member' : name,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                            if (action.isNotEmpty)
                              TextSpan(
                                text: ' $action',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: tokens.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style:
                            TextStyle(fontSize: 12, color: tokens.textTertiary),
                      ),
                    ],
                    if (isOwner) ...[
                      const SizedBox(width: 2),
                      _RowMenuButton(pending: pending, onTap: onMenu),
                    ],
                  ],
                ),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12.5, color: tokens.textTertiary),
                  ),
                ],
                if (target.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    target,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ],
                // Suppressed when it merely repeats something already on
                // screen. `activityDescriptionLabel` falls back to the action
                // for several types, which is why a liked post used to read
                // "Sahil liked a post … liked a post".
                if (description.isNotEmpty &&
                    description != target &&
                    description.toLowerCase() != action.toLowerCase()) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: tokens.textTertiary,
                    ),
                  ),
                ],
                if (isOwner) ...[
                  const SizedBox(height: 8),
                  _VisibilityChip(isPublic: activityIsPublic(activity)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact 28px overflow trigger, vertically centered with the date in the
/// row header. Shows a small spinner (and ignores taps) while the row's
/// mutation is in flight.
class _RowMenuButton extends StatelessWidget {
  const _RowMenuButton({required this.pending, this.onTap});

  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Semantics(
      button: true,
      label: 'Activity options',
      child: InkResponse(
        onTap: pending ? null : onTap,
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: pending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.more_horiz, size: 18, color: tokens.textTertiary),
          ),
        ),
      ),
    );
  }
}

/// Owner-only visibility indicator: who can see this activity.
class _VisibilityChip extends StatelessWidget {
  const _VisibilityChip({required this.isPublic});

  final bool isPublic;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final t = ProfileSurfaceTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      // Tone only: it states who can see the row, it is not a control.
      decoration: BoxDecoration(
        color: t.raisedFill,
        borderRadius: BorderRadius.circular(ProfileSurfaceTokens.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPublic ? Icons.public : Icons.lock_outline,
            size: 12,
            color: tokens.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            isPublic ? 'Public' : 'Private',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: tokens.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Body section cards (read-only-aware) ─────────────────────────────────────

class ExperienceSectionCard extends StatelessWidget {
  const ExperienceSectionCard({
    super.key,
    required this.entries,
    required this.editable,
    this.onAdd,
    this.onEdit,
  });

  final List<ProfileEntry> entries;
  final bool editable;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One action per section: "+" when empty, edit once it has data.
          SectionHeader(
            icon: Icons.work_outline,
            title: 'Experience',
            showAdd: editable && entries.isEmpty,
            showEdit: editable && entries.isNotEmpty,
            onAdd: onAdd,
            onEdit: onEdit,
          ),
          if (entries.isEmpty)
            if (editable)
              const SectionEmptyState(
                icon: Icons.work_outline,
                title: 'Add your work experience',
                subtitle: "Let others know what you're working on.",
              )
            else
              const _SectionEmptyHint(text: 'No experience added yet.')
          else
            // Logos lead each role; no timeline line.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Up to five roles show outright.
                ...withFoldMark(visible: 5, [
                  for (var i = 0; i < entries.length; i++)
                    _entry(context, entries[i], i),
                ]),
              ],
            ),
        ],
      ),
    );
  }

  /// Uses the record's persisted accent colour when set. Entries without one
  /// render the neutral treatment — they used to be colour-coded by order
  /// (indigo → blue → amber), a rainbow that told the reader nothing. The
  /// "Now" role keeps its green badge, because that one does mean something.
  Widget _entry(BuildContext context, ProfileEntry entry, int index) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final custom = profileDisplayAccent(entry.accentColorHex);
    final isNow = (entry.trailingBadge ?? '').toLowerCase() == 'now';
    return EntryCard(
      entry: entry,
      accent: custom,
      badgeBackground: isNow
          ? tokens.successContainer
          : (custom?.withAlpha(28) ?? colors.surfaceContainerHigh),
      badgeForeground: isNow
          ? tokens.onSuccessContainer
          : (custom ?? colors.onSurfaceVariant),
    );
  }
}

class EducationSectionCard extends StatelessWidget {
  const EducationSectionCard({
    super.key,
    required this.entries,
    required this.editable,
    this.onAdd,
    this.onEdit,
  });

  final List<ProfileEntry> entries;
  final bool editable;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.school_outlined,
            title: 'Education',
            showAdd: editable && entries.isEmpty,
            showEdit: editable && entries.isNotEmpty,
            onAdd: onAdd,
            onEdit: onEdit,
          ),
          if (entries.isEmpty)
            if (editable)
              const SectionEmptyState(
                icon: Icons.school_outlined,
                title: 'Add your education',
                subtitle: 'Showcase your academic background.',
              )
            else
              const _SectionEmptyHint(text: 'No education added yet.')
          else
            // Up to three schools show outright.
            ...withFoldMark(visible: 3, [
              for (final entry in entries) EducationCard(entry: entry),
            ]),
        ],
      ),
    );
  }
}

class SkillsSectionCard extends StatelessWidget {
  const SkillsSectionCard({
    super.key,
    required this.categorized,
    required this.editable,
    this.categoryColors = const {},
    this.onAdd,
    this.onEdit,
  });

  final Map<String, List<String>> categorized;
  final bool editable;

  /// Saved per-category accent colours (category → hex, keyed uppercase).
  final Map<String, String> categoryColors;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.star_border,
            title: 'Skills',
            showAdd: editable && categorized.isEmpty,
            showEdit: editable && categorized.isNotEmpty,
            onAdd: onAdd,
            onEdit: onEdit,
          ),
          if (categorized.isEmpty)
            if (editable)
              const SectionEmptyState(
                icon: Icons.star_border,
                title: 'Add your skills',
                subtitle: 'Skills help recruiters and peers find you.',
              )
            else
              const _SectionEmptyHint(text: 'No skills added yet.')
          else
            ...withFoldMark(visible: 2, [
              for (final category in categorized.entries)
                SkillCategoryBlock(
                  title: category.key,
                  values: category.value,
                  accent: profileDisplayAccent(categoryColors[category.key]),
                ),
            ]),
        ],
      ),
    );
  }
}

/// Technical Skills (proficiency bars) — Self View only.
class TechnicalSkillsSectionCard extends StatelessWidget {
  const TechnicalSkillsSectionCard({super.key, required this.skills});

  final List<TechnicalSkill> skills;

  @override
  Widget build(BuildContext context) {
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.workspace_premium_outlined,
            title: 'Technical Skills',
          ),
          for (final skill in skills) TechnicalSkillRow(skill: skill),
        ],
      ),
    );
  }
}

class LanguagesSectionCard extends StatelessWidget {
  const LanguagesSectionCard({
    super.key,
    required this.languages,
    required this.editable,
    this.onAdd,
    this.onEdit,
  });

  final List<LanguageEntry> languages;
  final bool editable;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.language,
            title: 'Languages',
            showAdd: editable && languages.isEmpty,
            showEdit: editable && languages.isNotEmpty,
            onAdd: onAdd,
            onEdit: onEdit,
          ),
          if (languages.isEmpty)
            if (editable)
              const SectionEmptyState(
                icon: Icons.language,
                title: 'Add languages you speak',
                subtitle: 'Showcase your language skills.',
              )
            else
              const _SectionEmptyHint(text: 'No languages added yet.')
          else
            for (final language in languages) LanguageRow(language: language),
        ],
      ),
    );
  }
}

/// Compact muted line for an empty section when viewing someone else's profile
/// (no "add" prompt — it isn't the viewer's to fill).
class _SectionEmptyHint extends StatelessWidget {
  const _SectionEmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: tokens.textTertiary),
      ),
    );
  }
}

class ProjectsSectionCard extends StatelessWidget {
  const ProjectsSectionCard({
    super.key,
    required this.projects,
    required this.editable,
    this.onAdd,
    this.onEditProject,
  });

  final List<ProjectEntry> projects;
  final bool editable;

  /// Opens the Add Proof of Work form (the "+" affordance).
  final VoidCallback? onAdd;

  /// Opens the Edit Project form for a tapped tile.
  final ValueChanged<ProjectEntry>? onEditProject;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.image_outlined,
            title: 'Proof of Work',
            showAdd: editable,
            onAdd: onAdd,
          ),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            editable && onAdd != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 164,
                      child: AspectRatio(
                        aspectRatio: 1.18,
                        child: ProjectTile(isAddTile: true, onTap: onAdd),
                      ),
                    ),
                  )
                : Text(
                    'No projects added yet.',
                    style: TextStyle(fontSize: 13, color: tokens.textTertiary),
                  ),
          // One project per row, stacked. Plain Column children rather than a
          // nested list: a shrinkWrap list inside the page ListView
          // mis-measures its height deep in the scroll.
          for (int i = 0; i < projects.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
              child: ProjectViewTile(
                project: projects[i],
                index: i,
                onTap: editable && onEditProject != null
                    ? () => onEditProject!(projects[i])
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// One project, full width, as a bordered card: the cover image across the
/// top, then the title with a Live / Open source pill on the right, a
/// three-line summary, and the project's links as outlined pill buttons in
/// the bottom-right corner.
class ProjectViewTile extends StatelessWidget {
  const ProjectViewTile(
      {super.key, required this.project, required this.index, this.onTap});

  final ProjectEntry project;
  final int index;
  final VoidCallback? onTap;

  static const _sourceKinds = {WorkLinkKind.github, WorkLinkKind.gitlab};

  /// Every link the project carries, classified, without duplicates.
  List<WorkLink> get _links {
    final seen = <String>{};
    final out = <WorkLink>[];
    for (final raw in [project.linkUrl, ...project.additionalLinks]) {
      final link = detectWorkLink(raw);
      if (link != null && seen.add(link.href)) out.add(link);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final coverUrl = project.coverUrl;
    final summary = (project.description ?? '').trim().isNotEmpty
        ? project.description!.trim()
        : project.subtitle;
    final links = _links;
    final caseStudy = detectWorkLink(project.caseStudyUrl);
    final source = links.where((l) => _sourceKinds.contains(l.kind)).toList();
    final live = links.where((l) => !_sourceKinds.contains(l.kind)).toList();
    final status = source.isNotEmpty
        ? _ProjectStatus.openSource
        : live.isNotEmpty
            ? _ProjectStatus.live
            : null;
    final border = colors.onSurface.withValues(alpha: 0.12);
    final radius = BorderRadius.circular(18);
    // A tonal panel with a muted glyph when the project has no cover.
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHigh, colors.surfaceContainerHighest],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 28,
          color: colors.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label:
          [project.title, summary].where((p) => p.trim().isNotEmpty).join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: colors.onSurface.withValues(alpha: 0.03),
            borderRadius: radius,
            border: Border.all(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: coverUrl != null && coverUrl.isNotEmpty
                      ? Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => placeholder,
                          frameBuilder: (_, child, frame, sync) => sync
                              ? child
                              : AnimatedOpacity(
                                  opacity: frame == null ? 0 : 1,
                                  duration: const Duration(milliseconds: 180),
                                  child: child,
                                ),
                        )
                      : placeholder,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            project.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(width: 10),
                          _ProjectStatusPill(status: status),
                        ],
                      ],
                    ),
                    if (summary.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.78),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (links.isNotEmpty ||
                        caseStudy != null ||
                        project.techStack.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // One line, always: a narrow card scales the
                          // tiles down rather than wrapping them.
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final (i, t)
                                      in project.techStack.take(4).indexed) ...[
                                    if (i > 0) const SizedBox(width: 5),
                                    _TechTile(name: t),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              if (caseStudy != null)
                                _ProjectLinkButton(
                                  glyph: Icon(Icons.article_outlined,
                                      size: 16, color: colors.onSurface),
                                  label: 'Case study',
                                  onTap: () =>
                                      openProfileLink(context, caseStudy),
                                ),
                              for (final l in source)
                                _ProjectLinkButton(
                                  glyph: workLinkGlyph(l.kind,
                                      size: 15, color: colors.onSurface),
                                  label: l.label,
                                  onTap: () => openProfileLink(context, l),
                                ),
                              if (live.isNotEmpty)
                                _ProjectLinkButton(
                                  glyph: Icon(Icons.arrow_outward_rounded,
                                      size: 16, color: colors.onSurface),
                                  label: 'Live',
                                  onTap: () =>
                                      openProfileLink(context, live.first),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ProjectStatus { live, openSource }

/// The tinted status pill beside a project's title: a green dot for Live, a
/// violet wash for Open source.
class _ProjectStatusPill extends StatelessWidget {
  const _ProjectStatusPill({required this.status});

  final _ProjectStatus status;

  static const _green = Color(0xFF3DDC84);
  static const _violet = Color(0xFFA78BFA);

  @override
  Widget build(BuildContext context) {
    final live = status == _ProjectStatus.live;
    final hue = live ? _green : _violet;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: hue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: _green, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            live ? 'Live' : 'Open source',
            style: TextStyle(
              color: hue,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// An outlined pill button for one of a project's links.
class _ProjectLinkButton extends StatelessWidget {
  const _ProjectLinkButton({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final Widget glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final radius = BorderRadius.circular(999);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: radius,
              border:
                  Border.all(color: colors.onSurface.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                glyph,
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
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

/// One technology a project uses, as a small tinted tile with its mark (or
/// its initials when there is no mark for it). The name is the tooltip.
class _TechTile extends StatelessWidget {
  const _TechTile({required this.name});

  final String name;

  static const Map<String, (FaIconData, Color)> _marks = {
    'react': (FontAwesomeIcons.react, Color(0xFF61DAFB)),
    'node.js': (FontAwesomeIcons.nodeJs, Color(0xFF8CC84B)),
    'node': (FontAwesomeIcons.nodeJs, Color(0xFF8CC84B)),
    'javascript': (FontAwesomeIcons.js, Color(0xFFF7DF1E)),
    'python': (FontAwesomeIcons.python, Color(0xFF4B8BBE)),
    'go': (FontAwesomeIcons.golang, Color(0xFF00ADD8)),
    'docker': (FontAwesomeIcons.docker, Color(0xFF2496ED)),
    'aws': (FontAwesomeIcons.aws, Color(0xFFFF9900)),
    'figma': (FontAwesomeIcons.figma, Color(0xFFF24E1E)),
    'android': (FontAwesomeIcons.android, Color(0xFF3DDC84)),
    'apple': (FontAwesomeIcons.apple, Color(0xFFE6E6E6)),
    'ios': (FontAwesomeIcons.apple, Color(0xFFE6E6E6)),
    'html': (FontAwesomeIcons.html5, Color(0xFFE34F26)),
    'css': (FontAwesomeIcons.css3Alt, Color(0xFF2965F1)),
    'git': (FontAwesomeIcons.gitAlt, Color(0xFFF05032)),
    'angular': (FontAwesomeIcons.angular, Color(0xFFDD0031)),
    'vue': (FontAwesomeIcons.vuejs, Color(0xFF42B883)),
    'java': (FontAwesomeIcons.java, Color(0xFFED8B00)),
    'rust': (FontAwesomeIcons.rust, Color(0xFFDEA584)),
    'flutter': (FontAwesomeIcons.mobileScreen, Color(0xFF54C5F8)),
    'typescript': (FontAwesomeIcons.code, Color(0xFF3178C6)),
    'storybook': (FontAwesomeIcons.bookOpen, Color(0xFFFF4785)),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final mark = _marks[name.trim().toLowerCase()];
    final hue = mark?.$2 ?? colors.onSurface;
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, math.min(2, name.trim().length));
    return Tooltip(
      message: name,
      child: Semantics(
        label: name,
        excludeSemantics: true,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: hue.withValues(alpha: 0.35)),
          ),
          child: mark != null
              ? FaIcon(mark.$1, size: 12, color: hue)
              : Text(
                  initials,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: hue,
                  ),
                ),
        ),
      ),
    );
  }
}
