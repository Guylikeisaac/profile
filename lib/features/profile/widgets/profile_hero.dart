import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/theme/semantic_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/glass/glass.dart';
import '../../chat/navigation/open_direct_chat.dart' show MessageAvailability;
import '../data/profile_view_data.dart';
import 'profile_entry_cards.dart' show profileAccentFromHex;
import 'profile_motion.dart';
import 'profile_surface.dart';

// ── Cover geometry ───────────────────────────────────────────────────────────

/// The cover is a wide, short banner — about 2.7 : 1 — not a backdrop for the
/// whole hero.
const double _kCoverAspectRatio = 2.7;

/// Bounds on that ratio's height: a 320pt phone would otherwise get a sliver,
/// and a tablet a billboard.
const double _kCoverMinHeight = 124;
const double _kCoverMaxHeight = 220;

/// The avatar, *including* its page-coloured ring, and how much of it rides
/// above the cover's lower edge (half: it is centred on the edge).
const double _kAvatarSize = 104;
const double _kAvatarRing = 4;
const double _kAvatarOverlap = _kAvatarSize / 2;

/// The edit badge is a 28pt disc inside a 44pt hit box, so the hit box hangs
/// this far outside the avatar. [_Avatar] is sized to contain it — a child that
/// overflows its parent's bounds is painted but never hit-tested.
const double _kBadgeSize = 28;
const double _kBadgeHitSize = 44;
const double _kBadgeOverhang = 2 + (_kBadgeHitSize - _kBadgeSize) / 2;

/// How far below the banner's lower edge the hero's top box extends: the
/// avatar's lower half plus the badge's overhang.
const double _kAvatarBelow = (_kAvatarSize - _kAvatarOverlap) + _kBadgeOverhang;

/// The hero's horizontal gutter — the avatar's left edge and the identity's.
const double _kHeroGutter = 20;

/// Top-bar band under the status bar: 8 above, a 44pt row of controls, 4 below.
const double _kTopBarTopGap = 8;
const double _kTopBarBand = _kTopBarTopGap + 44 + 4;

/// The cover's height for a given width and status-bar inset.
///
/// `width / 2.7`, clamped — and never shorter than what the chrome drawn *on*
/// the cover needs: the status bar, the back/share row, then the avatar's upper
/// half. Without that floor a tall status bar (59pt on a Dynamic Island phone)
/// pushes the controls down into the row the avatar already occupies. The floor
/// only ever bites on those phones, where it lands near 2.4 : 1.
@visibleForTesting
double profileCoverHeight({required double width, required double topInset}) {
  final banner =
      (width / _kCoverAspectRatio).clamp(_kCoverMinHeight, _kCoverMaxHeight);
  final chromeFloor = topInset + _kTopBarBand + _kAvatarOverlap;
  return banner < chromeFloor ? chromeFloor : banner;
}

/// Keys for the widget tests (`profile_hero_cover_test.dart`).
@visibleForTesting
const Key profileCoverKey = ValueKey('profile-hero-cover');
@visibleForTesting
const Key profileAvatarKey = ValueKey('profile-hero-avatar');
@visibleForTesting
const Key profileAvatarEditKey = ValueKey('profile-hero-avatar-edit');
@visibleForTesting
const Key profileIdentityKey = ValueKey('profile-hero-identity');
@visibleForTesting
const Key profileCoverFadeKey = ValueKey('profile-hero-cover-fade');

/// A dark cover gradient tinted by the saved cover colour [hex].
///
/// The colour is pushed dark via HSL (top ~0.30 L, bottom ~0.16 L) so the white
/// controls drawn over the cover stay readable for any chosen hue.
/// Null/unparseable → the neutral near-black pair the profile surface tokens
/// carry (`coverTop` → `coverBottom`, the graphite ramp). The default used to
/// be the theme's deep-indigo hero tokens, which put a saturated purple slab
/// at the top of an otherwise restrained near-black app.
///
/// **The cover stays dark in both themes.** It is the one dark band at the top
/// of a light page, which is also what keeps the (always light) status-bar
/// icons legible; the tint comes from the user's own saved cover colour —
/// content, not chrome.
List<Color> _heroColors(ProfileSurfaceTokens t, String? hex) {
  final base = profileAccentFromHex(hex);
  if (base == null) {
    return [t.coverTop, t.coverBottom];
  }
  // Monochrome: the saved colour keeps its *weight* (a light hue reads as a
  // slightly lighter grey) but never its hue.
  final hsl = HSLColor.fromColor(base).withSaturation(0);
  final top = (0.08 + hsl.lightness * 0.12).clamp(0.08, 0.20);
  return [
    hsl.withLightness(top).toColor(),
    t.coverBottom,
  ];
}

String _workDetailsLine(ProfileViewData data) {
  final parts = [data.department, data.industry]
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  return parts.join(' · ');
}

/// Role subtitle under the name. CV is the only view that appends the current
/// company. Built from non-empty parts only, so a profile with no role/company
/// simply omits the line instead of rendering placeholders or a stray "·".
String _subtitleLine(ProfileViewMode mode, ProfileViewData data) {
  final parts = [
    data.role,
    if (mode.isCv) data.company,
  ].where((part) => part.trim().isNotEmpty).toList(growable: false);
  return parts.join(' · ');
}

/// Presentation state for the public-profile Connect button, derived from the
/// real connection relationship (see `PublicConnectKind`).
enum HeroConnectState {
  /// "Connect" (solid brand) — send a request.
  connect,

  /// "Requested" (muted pending fill + clock) — withdraw the outgoing request.
  requested,

  /// "Accept" (solid brand) — accept the incoming request.
  incoming,

  /// "Connected" (outline + check, disabled).
  connected,

  /// In-flight action — disabled.
  busy,

  /// Hidden (self-profile) — no Connect button.
  hidden,
}

/// The identity hero shared by all three profile views: a compact cover, the
/// avatar riding its lower edge, and the identity block on the page below.
///
/// ```
/// ┌──────────────────────────────┐ ← status bar, under the cover
/// │ (←)                 (Share)  │
/// │           cover  ~2.7 : 1    │
/// │            ╭──────╮          │
/// └────────────┤avatar├──────────┘ ← avatar centred on the lower edge
///              ╰──────╯
///               Name
///          role · company              ← everything from here down sits on
///        location · Open to Work         the ordinary page surface
///        [ actions ]   [ stats ]
/// ```
///
/// The cover used to be the background of this *entire* block, which made a
/// banner photo a ~520pt backdrop with the name, buttons and stats printed over
/// it. It is now a banner; see [profileCoverHeight] for how it is sized. No
/// text is drawn on the photo, so the photo is shown as uploaded — no 50%
/// darkening — with only a short scrim under the status bar and the controls.
///
/// The banner's *frame* ends at the avatar's centre, but its picture does not:
/// it continues behind the avatar and dissolves into the page by the time it
/// reaches the name, so a photo never ends in a straight line above the
/// identity. See [_Cover].
///
/// The block still adapts its **chrome** to [mode]: top bar (back / share vs
/// brand logo / copy-link / share), avatar edit badge, subtitle (with company
/// on CV), status treatment (inline text vs filled pills), primary actions, and
/// a 3- vs 4-column stats card.
class ProfileHero extends StatelessWidget {
  const ProfileHero({
    super.key,
    required this.mode,
    required this.data,
    this.onBack,
    this.onShare,
    this.onCopyLink,
    this.onEditProfile,
    this.onEditAvatar,
    this.onOverflow,
    this.onConnect,
    this.onMessage,
    this.onMessageBlocked,
    this.messageState = MessageAvailability.hidden,
    this.messageBlockedReason = '',
    this.connectState = HeroConnectState.connect,
    this.statsOverride,
    this.onConnectionsTap,
    this.coverImage,
    this.scrollOffset,
    this.overflowItems,
  });

  /// When given, the "…" toggles an inline menu of these under the action
  /// row (tap to open, tap again to close) instead of calling [onOverflow].
  final List<HeroMenuItem>? overflowItems;

  /// The page's scroll offset, driving the cover's parallax and its stretch
  /// on overscroll. Null → a still cover.
  final ValueListenable<double>? scrollOffset;

  final ProfileViewMode mode;
  final ProfileViewData data;

  /// Replaces the cover photo resolved from [ProfileViewData.bannerUrl]. The
  /// app never passes it; it lets a test supply decoded pixels of a chosen
  /// shape instead of reaching for the network.
  @visibleForTesting
  final ImageProvider? coverImage;

  /// Real hero stats computed by the screen (Connections/Profile Views/Yrs Exp).
  /// When non-null, replaces [ProfileViewData.socialStats] (which is mock) for
  /// the non-CV views. CV keeps its own resume stats.
  final List<ProfileStat>? statsOverride;

  /// Tapping the "Connections" stat opens the accepted-connections view. Only
  /// wired on the self profile (null → the stat is not tappable).
  final VoidCallback? onConnectionsTap;

  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;
  final VoidCallback? onEditProfile;
  final VoidCallback? onEditAvatar;
  final VoidCallback? onOverflow;
  final VoidCallback? onConnect;
  final VoidCallback? onMessage;

  /// Tapped when Message is shown but unavailable — explains why.
  final VoidCallback? onMessageBlocked;

  /// Whether a Message button should appear at all, and in what state. Derived
  /// from the real connection relationship; see `messageAvailabilityFor`.
  final MessageAvailability messageState;

  /// Copy for the unavailable state.
  final String messageBlockedReason;
  final HeroConnectState connectState;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final t = ProfileSurfaceTokens.of(context);
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final coverHeight =
        profileCoverHeight(width: media.size.width, topInset: topInset);
    final cover = coverImage ?? cachedImageProvider(data.bannerUrl);
    final subtitle = _subtitleLine(mode, data);
    final workDetails = _workDetailsLine(data);
    final stats =
        statsOverride ?? (mode.isCv ? data.resumeStats : data.socialStats);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cover + the avatar's lower half, which hangs off the banner's
        // bottom-left corner. Sized to contain the avatar and its edit badge's
        // hit box, so nothing paints outside its bounds.
        SizedBox(
          height: coverHeight + _kAvatarBelow,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: coverHeight,
                child: _Parallax(
                  offset: scrollOffset,
                  height: coverHeight,
                  // Its own layer, so moving it is a translate of a cached
                  // picture rather than a repaint of photo + filter + fades.
                  child: RepaintBoundary(
                    child: _Cover(
                      key: profileCoverKey,
                      image: cover,
                      colors: _heroColors(t, data.bannerColor),
                      scrimHeight: topInset + _kTopBarBand,
                      fade: t.coverFade,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: topInset + _kTopBarTopGap,
                left: 12,
                right: 12,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: ProfileReveal(
                    offset: -12,
                    scale: 1,
                    duration: const Duration(milliseconds: 500),
                    child: _TopBar(
                      mode: mode,
                      onBack: onBack,
                      onShare: onShare,
                      onCopyLink: onCopyLink,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: coverHeight - _kAvatarOverlap - _kBadgeOverhang,
                left: _kHeroGutter - _kBadgeOverhang,
                child: _AvatarEntrance(
                  child: _Avatar(
                    key: profileAvatarKey,
                    name: data.name,
                    avatarUrl: data.avatarUrl,
                    ringColor: t.avatarRing,
                    ringEdge: t.avatarRingEdge,
                    shadow: t.avatarShadow,
                    showEditBadge: mode.isSelf,
                    onEdit: onEditAvatar,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Identity: left-aligned, editorial — the name is the headline.
        Padding(
          key: profileIdentityKey,
          padding: const EdgeInsets.fromLTRB(_kHeroGutter, 14, _kHeroGutter, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _staggered([
              Text(
                data.name,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                  color: colors.onSurface,
                  height: 1.08,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    height: 1.3,
                    color: colors.onSurface.withValues(alpha: 0.86),
                  ),
                ),
              ],
              if (workDetails.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  workDetails.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.3,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _Status(
                mode: mode,
                location: data.location,
                openToWork: data.openToWork,
              ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 12),
                _StatsRow(
                  stats: stats,
                  onConnectionsTap: mode.isCv ? null : onConnectionsTap,
                ),
              ],
              if (mode != ProfileViewMode.cv) ...[
                const SizedBox(height: 16),
                _ActionsWithMenu(
                  items: overflowItems,
                  actions: (onToggle, open) => _HeroActions(
                    mode: mode,
                    onEditProfile: onEditProfile,
                    onOverflow: onToggle ?? onOverflow,
                    overflowOpen: open,
                    onConnect: onConnect,
                    onMessage: onMessage,
                    onMessageBlocked: onMessageBlocked,
                    messageState: messageState,
                    messageBlockedReason: messageBlockedReason,
                    connectState: connectState,
                  ),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

/// Gives each visible line of the identity block its own entrance, one after
/// another, so the header assembles itself top to bottom. Spacers pass
/// through untouched.
List<Widget> _staggered(List<Widget> children) {
  var i = 0;
  return [
    for (final child in children)
      if (child is SizedBox && child.child == null)
        child
      else
        ProfileReveal(
          delay: Duration(milliseconds: 260 + 90 * i++),
          child: child,
        ),
  ];
}

/// Moves the cover at half the scroll speed (it lags behind the page), and
/// stretches it when the page is pulled down past the top.
class _Parallax extends StatelessWidget {
  const _Parallax({
    required this.offset,
    required this.height,
    required this.child,
  });

  final ValueListenable<double>? offset;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listenable = offset;
    if (listenable == null || AppMotion.reducedMotion(context)) return child;
    return ValueListenableBuilder<double>(
      valueListenable: listenable,
      child: child,
      builder: (context, y, child) {
        if (y < 0) {
          // Overscroll: grow from the bottom edge to fill the gap.
          final scale = 1 + (-y / height);
          return Transform.translate(
            offset: Offset(0, y),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          );
        }
        // Darkened with a flat overlay rather than an Opacity layer: an
        // overlay is one rect per frame, an Opacity re-composites the whole
        // (greyscale-filtered) photo every frame.
        final dim = (y / (height * 1.2)).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, y * 0.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (dim > 0)
                ColoredBox(color: Colors.black.withValues(alpha: dim)),
            ],
          ),
        );
      },
    );
  }
}

/// The avatar pops in: scales up from 60% with a soft overshoot while fading
/// in, a beat after the cover.
class _AvatarEntrance extends StatefulWidget {
  const _AvatarEntrance({required this.child});

  final Widget child;

  @override
  State<_AvatarEntrance> createState() => _AvatarEntranceState();
}

class _AvatarEntranceState extends State<_AvatarEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reducedMotion(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _c, curve: Curves.elasticOut);
    final fade = CurvedAnimation(
        parent: _c, curve: const Interval(0, 0.35, curve: Curves.easeOut));
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1).animate(scale),
        child: widget.child,
      ),
    );
  }
}

// ── Cover ────────────────────────────────────────────────────────────────────

/// Desaturates the cover photo: the profile is strictly black and white, and
/// a full-colour banner would be the only hue on the page.
const ColorFilter _kGrayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// The banner: a neutral gradient with a fine dot grid when there is no
/// photo, or the photo in greyscale. Either way its lower half dissolves into
/// the page so the avatar and the name sit on one continuous black ground.
class _Cover extends StatelessWidget {
  const _Cover({
    super.key,
    required this.image,
    required this.colors,
    required this.scrimHeight,
    required this.fade,
  });

  final ImageProvider? image;
  final List<Color> colors;

  /// How far down the legibility scrim reaches under the status bar.
  final double scrimHeight;

  /// The page colour the picture dissolves into.
  final Color fade;

  @override
  Widget build(BuildContext context) {
    final photo = image;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
          ),
        ),
        if (photo == null)
          const CustomPaint(painter: _DotGridPainter())
        else ...[
          ColorFiltered(
            colorFilter: _kGrayscale,
            child: Image(
              image: photo,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) =>
                  const CustomPaint(painter: _DotGridPainter()),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: scrimHeight,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      fade.withValues(alpha: 0.55),
                      fade.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        // Lower half eases into the page.
        DecoratedBox(
          key: profileCoverFadeKey,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.35, 0.7, 1],
              colors: [
                fade.withValues(alpha: 0),
                fade.withValues(alpha: 0.6),
                fade,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A fine white dot grid — the photo-less cover's texture. Graphic rather
/// than ambient, and it fades with the rest of the cover.
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  static const double _step = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x1FFFFFFF);
    for (var y = _step / 2; y < size.height; y += _step) {
      for (var x = _step / 2; x < size.width; x += _step) {
        canvas.drawCircle(Offset(x, y), 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => false;
}

// ── Top bar ────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    this.onBack,
    this.onShare,
    this.onCopyLink,
  });

  final ProfileViewMode mode;
  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    if (mode.isCv) {
      // Brand-forward export header: logo (left) · Copy Link + share (right).
      //
      // Three items is one more than a 320pt phone has room for at a large
      // text size, so the row gives way in a fixed order instead of
      // overflowing: the wordmark goes first (the "S" mark alone still says
      // whose export this is), then the Copy Link label ellipsises. The two
      // actions themselves never shrink.
      return LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            _BrandLockup(showWordmark: constraints.maxWidth >= 340),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: ProfileGlassPill(
                      icon: Icons.link,
                      label: 'Copy Link',
                      onTap: onCopyLink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CoverIconButton(
                    icon: Icons.ios_share,
                    semanticLabel: 'Share',
                    onTap: onShare,
                    iconSize: 19,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Self / Public: back (left) · Share (right). Settings lives in the
    // profile drawer, not here — the hero icon was a dead toast stub.
    //
    // Both are compact charcoal glass discs, legible over a bright photo (the
    // fill) and over a near-black one (the rim), and they dip on press like
    // every other glass control.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _CoverIconButton(
          icon: Icons.arrow_back_rounded,
          semanticLabel: 'Back',
          onTap: onBack,
        ),
        _CoverIconButton(
          icon: Icons.ios_share,
          semanticLabel: 'Share',
          onTap: onShare,
          iconSize: 19,
        ),
      ],
    );
  }
}

/// A round control drawn on the cover: black glass with a thin white edge,
/// white glyph. Reads over a bright greyscale photo (the fill) and over the
/// black cover (the edge). 44pt, the platform's minimum target.
class _CoverIconButton extends StatelessWidget {
  const _CoverIconButton({
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.iconSize = 21,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final double iconSize;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final ink = context.colorScheme.onSurface;
    final ground = context.colorScheme.surface;
    return GlassPressable(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(_size / 2),
      pressedScale: 0.92,
      builder: (context, s) => Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(ground.withValues(alpha: 0.55),
              ink.withValues(alpha: 0.18), s.press),
          border: Border.all(color: ink.withValues(alpha: 0.22)),
        ),
        child: Icon(icon,
            size: iconSize, color: ink, semanticLabel: semanticLabel),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({this.showWordmark = true});

  /// False on a narrow phone, where the mark stands alone.
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    // The shipped logo asset is a colour-on-light lockup; over the cover we
    // render a white wordmark with the brand "S" mark, on the same dark chip
    // the controls use — a cover photo can be any colour, white included.
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: EdgeInsets.fromLTRB(5, 5, showWordmark ? 12 : 5, 5),
      decoration: _coverChipDecoration(tokens, BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primary, colors.primary],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'S',
              style: TextStyle(
                color: colors.onPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          if (showWordmark) ...[
            const SizedBox(width: 7),
            Text(
              'SyncUp',
              style: TextStyle(
                color: tokens.onMediaSurface,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The ground under anything drawn on the cover: a dark translucent chip with
/// a hairline edge. The dark fill carries white ink over a bright photo; the
/// edge keeps the chip visible over a near-black one.
BoxDecoration _coverChipDecoration(
  SyncUpSemantics tokens,
  BorderRadius? radius, {
  BoxShape shape = BoxShape.rectangle,
}) =>
    BoxDecoration(
      color: tokens.mediaSurface.withValues(alpha: 0.46),
      shape: shape,
      borderRadius: radius,
      border: Border.all(color: tokens.onMediaSurface.withValues(alpha: 0.18)),
    );

// ── Avatar ─────────────────────────────────────────────────────────────────

/// The avatar on its ring, plus the self profile's edit badge.
///
/// The ring is the page colour, not a translucent white: the avatar sits half
/// on the cover and half on the page, and a page-coloured ring is what cuts it
/// cleanly out of both — a white-at-30% ring vanishes on a light page and turns
/// muddy over a photo. A faint edge keeps the ring's outline readable where
/// the cover fades into the same colour, and a soft drop lifts the disc off
/// both grounds.
class _Avatar extends StatelessWidget {
  const _Avatar({
    super.key,
    required this.name,
    required this.showEditBadge,
    required this.ringColor,
    required this.ringEdge,
    required this.shadow,
    this.avatarUrl = '',
    this.onEdit,
  });

  final String name;
  final bool showEditBadge;
  final Color ringColor;
  final Color ringEdge;
  final List<BoxShadow> shadow;
  final String avatarUrl;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    // Padded by the badge's overhang on every side (so the disc stays centred),
    // which puts the badge's whole 44pt hit box inside this widget's bounds.
    return SizedBox(
      width: _kAvatarSize + _kBadgeOverhang * 2,
      height: _kAvatarSize + _kBadgeOverhang * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ProfileOrbitRing(
            size: _kAvatarSize,
            color: ringEdge,
            child: Container(
              width: _kAvatarSize,
              height: _kAvatarSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ringColor,
                shape: BoxShape.circle,
                boxShadow: shadow,
              ),
              child: AppUserAvatar(
                name: name,
                avatarUrl: avatarUrl,
                size: _kAvatarSize - _kAvatarRing * 2,
              ),
            ),
          ),
          if (showEditBadge)
            Positioned(
              right: 0,
              bottom: 0,
              child: Semantics(
                button: true,
                enabled: onEdit != null,
                label: 'Change profile photo',
                excludeSemantics: true,
                onTap: onEdit,
                child: GestureDetector(
                  key: profileAvatarEditKey,
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: onEdit,
                  child: SizedBox(
                    width: _kBadgeHitSize,
                    height: _kBadgeHitSize,
                    child: Center(
                      child: Container(
                        width: _kBadgeSize,
                        height: _kBadgeSize,
                        decoration: BoxDecoration(
                          // The CTA pair: brand in light, near-white in dark.
                          // A blue disc on the avatar was the first accent the
                          // eye met on a dark profile, ahead of the name.
                          color: tokens.ctaFill,
                          shape: BoxShape.circle,
                          border: Border.all(color: ringColor, width: 2.5),
                        ),
                        child: Icon(Icons.photo_camera_outlined,
                            size: 14, color: tokens.onCtaFill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Status (inline vs filled pills) ──────────────────────────────────────────

/// The "Open to Work" dot: a live green, the one status colour in the hero.
const Color kOpenToWorkGreen = Color(0xFF22C55E);

class _Status extends StatelessWidget {
  const _Status({
    required this.mode,
    required this.location,
    required this.openToWork,
  });

  final ProfileViewMode mode;
  final String location;

  /// Real backend flag (work-details `jobSeekingStatus`). The badge renders
  /// ONLY when the user actually enabled it — never as decoration.
  final bool openToWork;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final place = location.trim();
    // Neither signal saved → no status row at all.
    if (!openToWork && place.isEmpty) return const SizedBox.shrink();

    // One chip language in every mode: "Open to Work" is a black chip with a
    // bright edge and a pulsing green dot — the signal a recruiter scans for — and
    // the location is a quieter outlined chip beside it.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (openToWork)
          // Black, with a crisp white edge and a live green pulse.
          _StatusChip(
            label: 'Open to Work',
            leading: const ProfilePulseDot(color: kOpenToWorkGreen),
            fill: colors.surface,
            ink: colors.onSurface,
            edge: colors.onSurface.withValues(alpha: 0.85),
          ),
        // No saved location → no chip (honest empty state, no mock city).
        if (place.isNotEmpty)
          _StatusChip(
            label: place,
            leading: Icon(Icons.location_on_outlined,
                size: 14, color: colors.onSurface.withValues(alpha: 0.8)),
            fill: Colors.transparent,
            ink: colors.onSurface.withValues(alpha: 0.86),
            edge: colors.onSurface.withValues(alpha: 0.22),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.leading,
    required this.fill,
    required this.ink,
    required this.edge,
  });

  final String label;
  final Widget leading;
  final Color fill;
  final Color ink;
  final Color edge;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action buttons ───────────────────────────────────────────────────────────

class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.mode,
    this.onEditProfile,
    this.onOverflow,
    this.overflowOpen = false,
    this.onConnect,
    this.onMessage,
    this.onMessageBlocked,
    this.connectState = HeroConnectState.connect,
    this.messageState = MessageAvailability.hidden,
    this.messageBlockedReason = '',
  });

  final ProfileViewMode mode;
  final VoidCallback? onEditProfile;
  final VoidCallback? onOverflow;
  final bool overflowOpen;
  final VoidCallback? onConnect;
  final VoidCallback? onMessage;
  final VoidCallback? onMessageBlocked;
  final HeroConnectState connectState;
  final MessageAvailability messageState;
  final String messageBlockedReason;

  @override
  Widget build(BuildContext context) {
    if (mode.isSelf) {
      // Edit Profile (solid, full width) · … (overflow). "Add custom button"
      // is gone — it was a dead toast stub with no backing feature.
      return Row(
        children: [
          Expanded(
            child: HeroPillButton(
              label: 'Edit Profile',
              solid: true,
              onTap: onEditProfile,
            ),
          ),
          const SizedBox(width: 10),
          HeroOverflowButton(onTap: onOverflow, open: overflowOpen),
        ],
      );
    }

    // Public: a state-aware Connect button + Message (outline). The Connect
    // button is hidden on the self-preview, and disabled while an action is in
    // flight or when already connected.
    final connect = _connectButton();
    final message = _messageButton();
    return Row(
      children: [
        if (connect != null) ...[
          Expanded(child: _ConnectSwap(state: connectState, child: connect)),
          if (message != null) const SizedBox(width: 10),
        ],
        if (message != null) Expanded(child: message),
        // Someone else's profile: the same "…" the self view carries, in the
        // same place. It is the only way to reach Remove connection, Block and
        // Report from a profile, so it shows in *every* relationship state —
        // including "Connected", whose pill is deliberately inert. The screen
        // passes no callback on the self-preview, where none of those apply.
        if (onOverflow != null) ...[
          if (connect != null || message != null) const SizedBox(width: 10),
          HeroOverflowButton(onTap: onOverflow, open: overflowOpen),
        ],
      ],
    );
  }

  /// The Message button, or null when there is nothing honest to show.
  ///
  /// chat-service only accepts messages between **accepted connections**, so an
  /// always-enabled Message button is a promise the backend will refuse: the
  /// thread would open, history would 403, and the first send would vanish. The
  /// three states here match what the server will actually do —
  ///
  ///  * connected → live button;
  ///  * not connected / request pending either way → dimmed, and tapping
  ///    explains what to do instead of failing silently;
  ///  * self, or the relationship not resolved yet → nothing, because an
  ///    enabled button that turns disabled a moment later is worse than one
  ///    that arrives a moment late.
  Widget? _messageButton() {
    switch (messageState) {
      case MessageAvailability.hidden:
        return null;
      case MessageAvailability.enabled:
        return HeroPillButton(
          label: 'Message',
          solid: false,
          onTap: onMessage,
        );
      case MessageAvailability.needsConnection:
        return HeroPillButton(
          label: 'Message',
          solid: false,
          dimmed: true,
          semanticHint: messageBlockedReason,
          // Still tappable on purpose: the tap is the only place the reason
          // can be delivered on a phone, where there is no hover.
          onTap: onMessageBlocked,
        );
    }
  }

  /// Builds the public Connect button for the current [connectState], or null
  /// when it should be hidden (self-preview).
  ///
  /// The four live states must be told apart at a glance, because they ask for
  /// four different things. "Connect" and "Accept" are the actionable pair and
  /// keep the solid brand fill; "Requested" is *pending* — still tappable, but
  /// nothing is owed to it — and wears the muted neutral tier instead of the
  /// same outline "Connected" and "Message" use. Requested and Connected also
  /// carry opposite glyphs (a clock vs a check), so the two never read as the
  /// same pill with different words.
  Widget? _connectButton() {
    switch (connectState) {
      case HeroConnectState.hidden:
        return null;
      case HeroConnectState.connect:
        return HeroPillButton(label: 'Connect', solid: true, onTap: onConnect);
      case HeroConnectState.requested:
        return HeroPillButton(
          label: 'Requested',
          solid: false,
          pending: true,
          icon: Icons.schedule,
          onTap: onConnect,
          // Says what happened *and* what the tap does: the label alone reads
          // as a status, and a screen-reader user has no colour to tell them
          // it is still a button.
          semanticLabel: 'Connection request sent. Tap to withdraw request.',
        );
      case HeroConnectState.incoming:
        return HeroPillButton(label: 'Accept', solid: true, onTap: onConnect);
      case HeroConnectState.connected:
        // A settled state, not an action: no tap, no pane.
        return const HeroPillButton(
          label: 'Connected',
          solid: false,
          settled: true,
          icon: Icons.check,
          onTap: null,
        );
      case HeroConnectState.busy:
        return const HeroPillButton(
          label: 'Working…',
          solid: true,
          busy: true,
          onTap: null,
        );
    }
  }
}

/// Cross-fades the Connect button as the relationship state changes.
///
/// Sending a request is a small confirmation, not an event: the button is the
/// same control in a new mood, so the swap is a 200ms fade with a 0.98 → 1
/// settle and nothing else — no bounce, no celebration. Both children are laid
/// out in the [Expanded] slot the caller already gave the button, so the pill
/// keeps its width and the hero cannot reflow while the fade runs.
///
/// Under reduced motion [AppMotion.durationFor] collapses this to a single
/// frame and the scale is dropped entirely, leaving a plain opacity change.
class _ConnectSwap extends StatelessWidget {
  const _ConnectSwap({required this.state, required this.child});

  final HeroConnectState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reducedMotion(context);
    return AnimatedSwitcher(
      duration: AppMotion.durationFor(context, AppMotion.enter),
      switchInCurve: AppMotion.curveFor(context, AppMotion.enterCurve),
      switchOutCurve: AppMotion.curveFor(context, AppMotion.exitCurve),
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (reduced) return fade;
        return ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
          child: fade,
        );
      },
      child: KeyedSubtree(key: ValueKey(state), child: child),
    );
  }
}

/// One action in the hero's row — the app's own [AppButton], at the compact
/// size, in the role the relationship calls for:
///
///  * **solid** — the screen's primary action ("Edit Profile", "Connect",
///    "Accept"): `AppButton.primary`, the lit near-white pane in dark, the same
///    CTA the auth funnel and onboarding end on;
///  * **secondary** — "Message", and the [pending] "Requested":
///    `AppButton.secondary`, charcoal glass. Pending also carries a clock, so
///    it is never the same pill as Message with different words;
///  * **settled** — "Connected": not an action at all, so not a button. An
///    edge, no fill, a check and secondary ink — a status drawn where a button
///    would be.
///
/// Compact because the public row holds three controls side by side: at the
/// regular size a 375pt phone ellipsises "Connected". Loading, disabled,
/// pressed and focus states are `AppButton`'s, unmodified.
class HeroPillButton extends StatelessWidget {
  const HeroPillButton({
    super.key,
    required this.label,
    required this.solid,
    this.onTap,
    this.dimmed = false,
    this.pending = false,
    this.settled = false,
    this.busy = false,
    this.icon,
    this.semanticHint,
    this.semanticLabel,
  })  : assert(
          !(solid && pending),
          'A pending pill is never the primary fill — pick one tier.',
        ),
        assert(!(solid && settled), 'A settled state is never the primary.');

  final String label;
  final bool solid;
  final VoidCallback? onTap;

  /// Renders the unavailable treatment.
  ///
  /// A null [onTap] alone is not enough: an inert pill looks exactly like a
  /// live one, so the user taps it and concludes the app is broken. Dimming
  /// says "not now" before the tap — and the tap still explains why.
  final bool dimmed;

  /// The **pending** state: an action the user has already taken that is now
  /// waiting on someone else. Secondary role plus a glyph; fully tappable (on
  /// this button the tap withdraws the request).
  final bool pending;

  /// A finished relationship ("Connected"): drawn as a status, not a control.
  final bool settled;

  /// A request in flight: the primary pane kept lit, with a spinner, taps
  /// blocked.
  final bool busy;

  /// A small leading glyph. Separates states that would otherwise differ only
  /// in wording — a clock for pending, a check for done.
  final IconData? icon;

  /// Read out in place of a tap for screen readers — the "why" that sighted
  /// users get from the tap's explanation.
  final String? semanticHint;

  /// Replaces the whole announcement when the visible label is a status and the
  /// tap does something the label does not name ("Requested" → withdraw).
  final String? semanticLabel;

  /// What a screen reader hears, or null to let the label speak for itself.
  String? get _announcement {
    if (semanticLabel != null) return semanticLabel;
    if (semanticHint != null) return '$label. $semanticHint';
    return null;
  }

  /// Below this width a glyph would push the label into an ellipsis
  /// ("Conn…" on a 320pt phone). The label is the part that carries meaning,
  /// so the glyph goes first; the states still differ in fill.
  static const double glyphMinWidth = 124;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _build(
        context,
        showGlyph: !constraints.hasBoundedWidth ||
            constraints.maxWidth >= glyphMinWidth,
      ),
    );
  }

  Widget _build(BuildContext context, {required bool showGlyph}) {
    final glyph = showGlyph ? icon : null;
    if (settled) return _SettledPill(label: label, icon: glyph);

    final button = AppButton(
      label: label,
      role: solid ? AppButtonRole.primary : AppButtonRole.secondary,
      onPressed: onTap,
      loading: busy,
      leading: glyph,
      size: AppButtonSize.compact,
    );
    final shown = dimmed ? Opacity(opacity: 0.5, child: button) : button;

    final announcement = _announcement;
    if (announcement == null) return shown;
    return Semantics(
      button: true,
      enabled: onTap != null && !dimmed,
      label: announcement,
      onTap: onTap,
      excludeSemantics: true,
      child: shown,
    );
  }
}

/// "Connected": the relationship is settled, so there is nothing to press.
///
/// Laid out exactly like the compact [AppButton] it stands in for (same
/// height, radius and label type), so the row does not jump when a request is
/// accepted — but painted as a status: the profile ladder's `settled` edge, no
/// fill, secondary ink.
class _SettledPill extends StatelessWidget {
  const _SettledPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final t = ProfileSurfaceTokens.of(context);
    final ink = colors.onSurfaceVariant;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        height: AppSpacing.minTapTarget,
        child: Center(
          child: SizedBox(
            height: HeroOverflowButton.visualSize,
            child: GlassSurface(
              spec: t.settled,
              borderRadius: AppRadii.controlAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: ink),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge(ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero's "…": a round liquid-glass button in the iOS manner — a
/// translucent body, a rim that catches light along its upper-left edge and
/// fades away below, a soft specular bloom near the top, and a squish on
/// press. While its menu is open it turns solid white and the "…" turns into
/// a close glyph.
class HeroOverflowButton extends StatelessWidget {
  const HeroOverflowButton({super.key, required this.onTap, this.open = false});

  final VoidCallback? onTap;

  /// Its menu is showing.
  final bool open;

  /// The visual diameter; the tap target is the platform's 48.
  static const double visualSize = 40;

  @override
  Widget build(BuildContext context) {
    final ink = context.colorScheme.onSurface;
    final d = AppMotion.durationFor(context, AppMotion.sheet);
    return SizedBox.square(
      dimension: AppSpacing.minTapTarget,
      child: GlassPressable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.minTapTarget / 2),
        pressedScale: 0.9,
        builder: (context, s) => Center(
          child: LiquidGlassCircle(
            size: visualSize,
            lit: math.max(s.press, s.hover * 0.5),
            solid: open,
            child: AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: d,
              curve: Curves.easeOutBack,
              child: AnimatedSwitcher(
                duration: AppMotion.durationFor(context, AppMotion.enter),
                transitionBuilder: (child, a) => ScaleTransition(
                  scale: a,
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: Icon(
                  open ? Icons.close_rounded : Icons.more_horiz_rounded,
                  key: ValueKey(open),
                  size: 20,
                  color: open
                      ? context.colorScheme.surface
                      : ink.withValues(alpha: 0.45 + 0.55 * s.enabled),
                  semanticLabel: open ? 'Close options' : 'More options',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular liquid-glass disc: layered gradients only (no backdrop blur,
/// which would re-render the page under it on every scroll frame).
///
/// [lit] (0–1) brightens it for press/hover; [solid] morphs it into an opaque
/// white disc.
class LiquidGlassCircle extends StatelessWidget {
  const LiquidGlassCircle({
    super.key,
    required this.size,
    required this.child,
    this.lit = 0,
    this.solid = false,
  });

  final double size;
  final Widget child;
  final double lit;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final d = AppMotion.durationFor(context, AppMotion.sheet);
    return AnimatedContainer(
      duration: d,
      curve: AppMotion.enterCurve,
      width: size,
      height: size,
      // The rim: a gradient ring, brightest at the upper left.
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            white.withValues(alpha: solid ? 1 : 0.55 + 0.25 * lit),
            white.withValues(alpha: solid ? 1 : 0.10),
            white.withValues(alpha: solid ? 1 : 0.28),
          ],
          stops: const [0, 0.55, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: white.withValues(alpha: 0.06 + 0.10 * lit),
            blurRadius: 14,
            spreadRadius: -2,
          ),
        ],
      ),
      child: AnimatedContainer(
        duration: d,
        curve: AppMotion.enterCurve,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // The body: translucent, a touch brighter at the top.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: solid
                ? const [white, white]
                : [
                    Color.lerp(
                        const Color(0xFF2A2A2A), const Color(0xFF3A3A3A), lit)!,
                    Color.lerp(
                        const Color(0xFF0E0E0E), const Color(0xFF1A1A1A), lit)!,
                  ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Specular bloom near the top-left.
            if (!solid)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.45, -0.6),
                      radius: 0.75,
                      colors: [
                        white.withValues(alpha: 0.30 + 0.15 * lit),
                        white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            // A faint lower lip, as light passing through the glass pools
            // at the bottom edge.
            if (!solid)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(0, 1.1),
                      radius: 0.6,
                      colors: [
                        white.withValues(alpha: 0.14),
                        white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

// ── Stats ────────────────────────────────────────────────────────────────────

/// The hero's numbers as one plain line: each value in regular weight with
/// its caption beside it in secondary ink. A tappable stat (the owner's Connections) gets
/// a small arrow and dims while pressed.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, this.onConnectionsTap});

  final List<ProfileStat> stats;
  final VoidCallback? onConnectionsTap;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          for (final stat in stats)
            _InlineStat(
              stat: stat,
              onTap: onConnectionsTap != null && stat.caption == 'Connections'
                  ? onConnectionsTap
                  : null,
            ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.stat, this.onTap});

  final ProfileStat stat;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        ProfileCountUp(
          value: stat.value,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontFeatures: AppTypography.tabularFigures,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          stat.caption.toLowerCase(),
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 3),
          Icon(Icons.arrow_outward_rounded,
              size: 13, color: colors.onSurfaceVariant),
        ],
      ],
    );
    if (onTap == null) {
      return Semantics(
        label: '${stat.value} ${stat.caption}',
        excludeSemantics: true,
        child: row,
      );
    }
    return Semantics(
      button: true,
      label: '${stat.value} ${stat.caption}',
      excludeSemantics: true,
      child: GlassPressable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(8),
        pressedScale: 0.97,
        builder: (context, s) => Opacity(
          opacity: 1 - 0.35 * math.max(s.press, s.hover * 0.5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Align(widthFactor: 1, child: row),
          ),
        ),
      ),
    );
  }
}

/// One row of the hero's inline "…" menu.
class HeroMenuItem {
  const HeroMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// The action row plus, under it, the "…" menu that unfolds in place when the
/// button is tapped and folds away when it is tapped again (or a row is
/// chosen). With no [items] it is just the action row.
class _ActionsWithMenu extends StatefulWidget {
  const _ActionsWithMenu({required this.items, required this.actions});

  final List<HeroMenuItem>? items;

  /// Builds the action row: the toggle to wire to the "…" (null when there
  /// is no inline menu) and whether the menu is open.
  final Widget Function(VoidCallback? onToggle, bool open) actions;

  @override
  State<_ActionsWithMenu> createState() => _ActionsWithMenuState();
}

class _ActionsWithMenuState extends State<_ActionsWithMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 300),
  );
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (AppMotion.reducedMotion(context)) {
      _c.value = _open ? 1 : 0;
    } else if (_open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  void _choose(HeroMenuItem item) {
    _toggle();
    item.onTap();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items == null || items.isEmpty) return widget.actions(null, false);

    final colors = context.colorScheme;
    final t = ProfileSurfaceTokens.of(context);
    final unfold = CurvedAnimation(
      parent: _c,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.actions(_toggle, _open),
        SizeTransition(
          sizeFactor: unfold,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: unfold,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.hairlineStrong),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) ProfileHairline(indent: 62),
                      _MenuRow(
                        item: items[i],
                        // Each row slides in a beat after the one above.
                        reveal: CurvedAnimation(
                          parent: _c,
                          curve: Interval(
                            (0.18 + 0.14 * i).clamp(0.0, 0.9),
                            (0.62 + 0.14 * i).clamp(0.1, 1.0),
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        ink: colors.onSurface,
                        onTap: () => _choose(items[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.reveal,
    required this.ink,
    required this.onTap,
  });

  final HeroMenuItem item;
  final Animation<double> reveal;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reveal,
      builder: (context, child) => Opacity(
        opacity: reveal.value,
        child: Transform.translate(
          offset: Offset(0, (1 - reveal.value) * -10),
          child: child,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashColor: ink.withValues(alpha: 0.08),
          highlightColor: ink.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ink.withValues(alpha: 0.22)),
                  ),
                  child: Icon(item.icon, size: 17, color: ink),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 13, color: ink.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
