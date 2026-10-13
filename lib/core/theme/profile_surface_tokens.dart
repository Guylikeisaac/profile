import 'package:flutter/material.dart';

import 'app_radii.dart';
import 'brand_palette.dart';
import 'color_schemes.dart';
import 'glass_tokens.dart';
import 'semantic_tokens.dart';

/// The profile's layered dark-surface system: one near-black canvas, and a
/// short ladder of translucent charcoal panes on it.
///
/// ## Why the profile needs its own set
///
/// Home and Network paint a single `surface` canvas with cards one tonal step
/// up. The profile stacks ten content sections, and inside them nested rows,
/// chips, wells and small controls — so it needs more rungs than two, and it
/// needs each rung to be a [GlassSpec] rather than a flat colour, so a card, a
/// nested row, a chip and a control read as the same glass at different
/// depths. Everything is derived from the graphite ramp and white/black at low
/// alpha; there is no hue here a designer did not already approve.
///
/// Buttons are **not** here. The hero's actions, sheet footers and resume
/// actions are `AppButton` / `SurfaceSpecs` — the app's one button language —
/// and this file only describes the panes those buttons sit on.
///
/// ## Depth comes from tone, not from outlines
///
/// The first pass of this ladder drew every pane with a clearly visible grey
/// rim, and ten stacked sections read as "dark mode with borders". The rule
/// now is that **tone separates tiers and the rim only catches light**: every
/// rim is brightest along the top edge (7–10% white) and fades to almost
/// nothing along the bottom, so a pane reads as a lit surface rather than a
/// box drawn around content. Each rung is one visible tonal step from the one
/// below it:
///
///  * **canvas** — the page: `colorScheme.surface`, `#0A0A0C`. Scaffold,
///    scroll and overscroll all show it.
///  * **card** — a section: `graphite900` easing slightly toward the canvas
///    at its foot (≈ `#131317` → `#111115`), a whisper of sheen, a top-lit
///    rim, and a soft shadow cast below.
///  * **raised** — a row *inside* a card (an education entry, the resume
///    file, a row in a sheet): white at 3–5% over whatever it sits on, lit at
///    the top edge only. Translucent on purpose, so the same tier works on a
///    card and on a sheet.
///  * **inset** — a well (a drop zone, a segmented track): darker than its
///    parent, with the light catching its lower lip instead of its top.
///  * **chip** — a tappable compact label (a social link): raised tone with a
///    slightly firmer rim, so it reads as something to press.
///  * **control** — a small round control (a section's add / edit).
///  * **settled** — a finished state that is not an action ("Connected"): no
///    fill, a faint edge.
///
/// No `BackdropFilter` anywhere: behind these panes is a flat near-black
/// canvas, and blurring flat colour returns flat colour — a blur pass per
/// card, per frame, for no visible difference.
///
/// ## Light
///
/// The app ships dark, but the light scheme still has to lay out (widget
/// tests pump it). Light resolves to the flat white-card language the light
/// theme already uses, so nothing there is glass-on-glass.
@immutable
class ProfileSurfaceTokens {
  const ProfileSurfaceTokens._({
    required this.canvas,
    required this.card,
    required this.cardPressed,
    required this.raised,
    required this.raisedPressed,
    required this.inset,
    required this.chip,
    required this.chipPressed,
    required this.control,
    required this.controlPressed,
    required this.settled,
    required this.raisedFill,
    required this.insetFill,
    required this.hairline,
    required this.hairlineStrong,
    required this.chipSurface,
    required this.coverTop,
    required this.coverBottom,
    required this.coverFade,
    required this.avatarRing,
    required this.avatarRingEdge,
    required this.avatarShadow,
    required this.successPillFill,
    required this.successPillEdge,
  });

  /// The active set for [context]'s theme.
  static ProfileSurfaceTokens of(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<SyncUpSemantics>() ?? SyncUpSemantics.light;
    return from(theme.colorScheme, tokens);
  }

  /// Builds the set for a scheme. Dark is the designed ladder above; light is
  /// the light theme's own flat cards, so the widgets need no branch.
  static ProfileSurfaceTokens from(ColorScheme colors, SyncUpSemantics tokens) {
    if (colors == SyncUpColorSchemes.mono) return _mono(colors, tokens);
    return colors.brightness == Brightness.dark
        ? _dark(colors, tokens)
        : _light(colors, tokens);
  }

  // ── Radii ──────────────────────────────────────────────────────────────────
  // The app's radius scale (`AppRadii`), named for the profile's tiers so a
  // widget says what it is rather than which number it wants.

  /// A section card.
  static const double cardRadius = AppRadii.card;

  /// A row nested inside a card, a well, a small control.
  static const double nestedRadius = AppRadii.control;

  /// A compact chip.
  static const double chipRadius = AppRadii.small;

  // ── Roles ──────────────────────────────────────────────────────────────────

  /// The page.
  final Color canvas;

  /// A section card, and how it responds when the whole card is tappable.
  final GlassSpec card;
  final GlassSpec cardPressed;

  /// A row inside a card (or inside a sheet).
  final GlassSpec raised;
  final GlassSpec raisedPressed;

  /// A well below its parent.
  final GlassSpec inset;

  /// A tappable compact chip (a social link).
  final GlassSpec chip;
  final GlassSpec chipPressed;

  /// A small round control disc.
  final GlassSpec control;
  final GlassSpec controlPressed;

  /// A settled, non-actionable state drawn where a button would be
  /// ("Connected"): an edge and no fill.
  final GlassSpec settled;

  /// Flat colours for elements too small to be a pane: a section glyph tile,
  /// a status badge, a progress track.
  final Color raisedFill;
  final Color insetFill;

  /// Separators. [hairline] between rows; [hairlineStrong] where a line has to
  /// carry across a raised pane (a stats divider, the timeline spine).
  final Color hairline;
  final Color hairlineStrong;

  /// The **effective opaque colour** of a chip's face on a card — what a brand
  /// glyph is actually drawn against, for contrast maths.
  final Color chipSurface;

  /// The cover's default falloff when there is no photo and no saved colour.
  /// Fixed in both themes: the cover is the one dark band on a light page.
  final Color coverTop;
  final Color coverBottom;

  /// The cover's lower edge fades into this — the canvas — so a photo lands on
  /// the page instead of ending in a hard line.
  final Color coverFade;

  /// The avatar's ring: the canvas colour, cutting the disc cleanly out of
  /// both the cover and the page, plus a faint edge and a soft drop.
  final Color avatarRing;
  final Color avatarRingEdge;
  final List<BoxShadow> avatarShadow;

  /// The "Open to Work" pill: a muted success surface with the success ink.
  final Color successPillFill;
  final Color successPillEdge;

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Color _white(double a) => BrandPalette.white.withValues(alpha: a);
  static Color _black(double a) => BrandPalette.mediaBlack.withValues(alpha: a);

  static BoxShadow _drop(double a, double blur, double y,
          [double spread = 0]) =>
      BoxShadow(
        color: _black(a),
        blurRadius: blur,
        offset: Offset(0, y),
        spreadRadius: spread,
      );

  static ProfileSurfaceTokens _dark(
      ColorScheme colors, SyncUpSemantics tokens) {
    final canvas = colors.surface;

    // Card: one tonal step off the canvas, easing back toward it at the foot,
    // lit along the top edge. The shadow is a whisper — on a near-black page
    // it deepens the ground under the card rather than drawing a halo.
    final card = GlassSpec(
      fillTop: BrandPalette.graphite900.withValues(alpha: 0.96),
      fillBottom: BrandPalette.graphite900.withValues(alpha: 0.78),
      sheen: _white(0.022),
      rimTop: _white(0.075),
      rimBottom: _white(0.018),
      shadows: [_drop(0.42, 18, 8, -8)],
    );
    final cardPressed = card.copyWith(
      fillTop: BrandPalette.graphite850.withValues(alpha: 0.96),
      fillBottom: BrandPalette.graphite900.withValues(alpha: 0.9),
      sheen: _white(0.03),
      rimTop: _white(0.10),
      rimBottom: _white(0.025),
      shadows: [_drop(0.36, 10, 4, -6)],
    );

    // Raised: white at a few percent over its parent — a card or a sheet —
    // with the light on its top edge only. No shadow: it sits *in* the card.
    final raised = GlassSpec(
      fillTop: _white(0.045),
      fillBottom: _white(0.028),
      sheen: _white(0.02),
      rimTop: _white(0.06),
      rimBottom: _white(0),
    );
    final raisedPressed = raised.copyWith(
      fillTop: _white(0.08),
      fillBottom: _white(0.055),
      rimTop: _white(0.09),
      rimBottom: _white(0.01),
    );

    // Inset: a well. Darker than its parent, and lit on the lower lip — the
    // edge of a recess that faces the light.
    final inset = GlassSpec(
      fillTop: _black(0.30),
      fillBottom: _black(0.22),
      rimTop: _white(0),
      rimBottom: _white(0.045),
    );

    // Chip: the raised tone with a firmer, still top-lit, rim — enough to say
    // "press me" without outlining the chip.
    final chip = GlassSpec(
      fillTop: _white(0.06),
      fillBottom: _white(0.04),
      sheen: _white(0.03),
      rimTop: _white(0.09),
      rimBottom: _white(0.025),
    );
    final chipPressed = chip.copyWith(
      fillTop: _white(0.11),
      fillBottom: _white(0.08),
      rimTop: _white(0.15),
      rimBottom: _white(0.05),
    );

    final control = GlassSpec(
      fillTop: _white(0.065),
      fillBottom: _white(0.04),
      sheen: _white(0.04),
      rimTop: _white(0.10),
      rimBottom: _white(0.025),
    );
    final controlPressed = control.copyWith(
      fillTop: _white(0.12),
      fillBottom: _white(0.09),
      rimTop: _white(0.16),
      rimBottom: _white(0.05),
    );

    final settled = GlassSpec(
      fillTop: _white(0.02),
      fillBottom: _white(0.01),
      rimTop: _white(0.14),
      rimBottom: _white(0.07),
    );

    // What a chip face resolves to over a card over the canvas.
    final cardFace = Color.alphaBlend(card.fillTop, canvas);
    final chipFace = Color.alphaBlend(chip.fillTop, cardFace);

    return ProfileSurfaceTokens._(
      canvas: canvas,
      card: card,
      cardPressed: cardPressed,
      raised: raised,
      raisedPressed: raisedPressed,
      inset: inset,
      chip: chip,
      chipPressed: chipPressed,
      control: control,
      controlPressed: controlPressed,
      settled: settled,
      raisedFill: _white(0.05),
      insetFill: _black(0.28),
      hairline: _white(0.07),
      hairlineStrong: _white(0.12),
      chipSurface: chipFace,
      coverTop: BrandPalette.graphite850,
      coverBottom: BrandPalette.graphite950,
      coverFade: canvas,
      avatarRing: canvas,
      avatarRingEdge: _white(0.08),
      avatarShadow: [_drop(0.45, 18, 6)],
      successPillFill: tokens.success.withValues(alpha: 0.10),
      successPillEdge: tokens.success.withValues(alpha: 0.26),
    );
  }

  /// The profile's strict black-and-white ladder (see `AppTheme.profileMono`).
  ///
  /// Flat, not glass: on a pure-black page, depth is a 1px neutral edge and a
  /// few percent of white — no sheen, no shadow, no hue. Every pane is lit
  /// evenly so the layout reads crisp and graphic rather than ambient.
  static ProfileSurfaceTokens _mono(
      ColorScheme colors, SyncUpSemantics tokens) {
    const canvas = Color(0xFF000000);
    GlassSpec flat(Color fill, Color rim, {double rimWidth = 1}) => GlassSpec(
          fillTop: fill,
          fillBottom: fill,
          rimTop: rim,
          rimBottom: rim,
          rimWidth: rimWidth,
        );

    const card = Color(0xFF0A0A0A);
    return ProfileSurfaceTokens._(
      canvas: canvas,
      card: flat(card, const Color(0xFF1F1F1F)),
      cardPressed: flat(const Color(0xFF121212), const Color(0xFF333333)),
      raised: flat(_white(0.035), _white(0.09)),
      raisedPressed: flat(_white(0.07), _white(0.16)),
      inset: flat(const Color(0xFF050505), _white(0.07)),
      chip: flat(canvas, _white(0.18)),
      chipPressed: flat(_white(0.08), _white(0.32)),
      control: flat(canvas, _white(0.22)),
      controlPressed: flat(_white(0.12), _white(0.45)),
      settled: flat(Colors.transparent, _white(0.28)),
      raisedFill: _white(0.06),
      insetFill: const Color(0xFF050505),
      hairline: _white(0.10),
      hairlineStrong: _white(0.16),
      chipSurface: canvas,
      coverTop: const Color(0xFF1C1C1C),
      coverBottom: canvas,
      coverFade: canvas,
      avatarRing: canvas,
      avatarRingEdge: _white(0.85),
      avatarShadow: const [],
      successPillFill: canvas,
      successPillEdge: _white(0.35),
    );
  }

  static ProfileSurfaceTokens _light(
      ColorScheme colors, SyncUpSemantics tokens) {
    final ink = colors.onSurface;
    Color inkAt(double a) => ink.withValues(alpha: a);
    GlassSpec flat(Color fill, Color rim,
            {List<BoxShadow> shadows = const []}) =>
        GlassSpec(
          fillTop: fill,
          fillBottom: fill,
          rimTop: rim,
          rimBottom: rim,
          shadows: shadows,
        );

    return ProfileSurfaceTokens._(
      canvas: colors.surface,
      card: flat(colors.surface, inkAt(0.08), shadows: tokens.cardShadow),
      cardPressed: flat(colors.surfaceContainerLow, inkAt(0.10),
          shadows: tokens.cardShadow),
      raised: flat(colors.surfaceContainerLow, inkAt(0.06)),
      raisedPressed: flat(colors.surfaceContainer, inkAt(0.10)),
      inset: flat(tokens.surfaceInset, inkAt(0.06)),
      chip: flat(colors.surfaceContainerLow, inkAt(0.10)),
      chipPressed: flat(colors.surfaceContainer, inkAt(0.14)),
      control: flat(colors.surfaceContainerHigh, inkAt(0.06)),
      controlPressed: flat(colors.surfaceContainerHighest, inkAt(0.10)),
      settled: flat(Colors.transparent, colors.outline),
      raisedFill: colors.surfaceContainerLow,
      insetFill: tokens.surfaceInset,
      hairline: inkAt(0.10),
      hairlineStrong: inkAt(0.16),
      chipSurface: colors.surfaceContainerLow,
      coverTop: BrandPalette.graphite850,
      coverBottom: BrandPalette.graphite950,
      coverFade: colors.surface,
      avatarRing: colors.surface,
      avatarRingEdge: inkAt(0.10),
      avatarShadow: tokens.cardShadow,
      successPillFill: tokens.successContainer,
      successPillEdge: tokens.success.withValues(alpha: 0.30),
    );
  }
}
