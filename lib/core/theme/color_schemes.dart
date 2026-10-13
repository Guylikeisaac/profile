import 'package:flutter/material.dart';

import 'brand_palette.dart';

/// The app's two [ColorScheme]s.
///
/// ## Why these are written out by hand
///
/// `ColorScheme.fromSeed` is deliberately **not** used. Seeding from
/// `BrandPalette.blue600` produces a tonal palette that does not contain
/// `#2962FF` itself — the generator would quantise SyncUp's brand colour to a
/// neighbouring tone — and it would invent surface tints nobody approved. These
/// schemes are explicit so the brand value survives and every surface tier is a
/// decision.
///
/// ## Light preserves what shipped
///
/// Before the theme system, `AppTheme.light` specified only nine roles and left
/// the rest at the `const ColorScheme.light()` defaults, which are degenerate:
/// `primaryContainer` equalled `primary`, every `surfaceContainer*` tier was
/// pure white, `onSurfaceVariant` equalled `onSurface`, and `outlineVariant`
/// was pure black.
///
/// Those nine roles are unchanged here. The rest are now filled in properly —
/// which is safe because almost nothing in the app reads the theme yet, and the
/// few framework widgets that *do* resolve the newly-populated roles
/// (dialogs, bottom sheets, popup menus, drawers, `ListTile`) are pinned back to
/// their previous rendering in the component themes. Those pins are marked and
/// come out as each feature migrates.
///
/// ## Dark is designed, not inverted
///
/// The dark scheme is not the light scheme flipped. Specifically:
///
///  * The page surface is `#0E1016`, not `#000000` — pure black smears on OLED
///    during scroll and leaves no room for a tier *below* the page.
///  * There are five distinct surface tiers, because the app's light design
///    already relies on three (the Network tab layers white cards on a grey
///    page) and dark mode must keep that separation without shadows.
///  * `primary` lifts from `#2962FF` to `#7C9BFF`. The brand blue on
///    `#0E1016` measures roughly 3.5:1, which fails AA for body and link text.
///    The brand mark itself keeps `#2962FF` — see `SyncUpSemantics`.
///  * `outline` and `outlineVariant` differ by more than in light, because a
///    single hairline value cannot be both an unobtrusive divider and a
///    perceptible input border on a dark ground.
abstract final class SyncUpColorSchemes {
  /// The light scheme. The nine roles specified before the theme system are
  /// byte-identical; everything else was previously degenerate.
  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,

    // ── Brand ────────────────────────────────────────────────────────────────
    // Unchanged from the pre-theme scheme.
    primary: BrandPalette.blue600,
    onPrimary: BrandPalette.white,

    // Previously equal to `primary`, which made every M3 container role render
    // as a solid brand block. Now the brand tint the app actually uses.
    primaryContainer: BrandPalette.blue50,
    onPrimaryContainer: BrandPalette.blue700,

    // Unchanged.
    secondary: BrandPalette.cyan300,
    onSecondary: BrandPalette.white,
    secondaryContainer: BrandPalette.cyan50,
    onSecondaryContainer: BrandPalette.ink900,

    // The lavender family the older selected states use.
    tertiary: BrandPalette.violet400,
    onTertiary: BrandPalette.white,
    tertiaryContainer: BrandPalette.violet50,
    onTertiaryContainer: BrandPalette.violet950,

    // ── Error ────────────────────────────────────────────────────────────────
    // `error` is unchanged. The app currently carries six near-identical
    // destructive reds across feature palettes; they converge here.
    error: BrandPalette.red600,
    onError: BrandPalette.white,
    errorContainer: BrandPalette.red50,
    onErrorContainer: BrandPalette.red600,

    // ── Surfaces ─────────────────────────────────────────────────────────────
    // `surface` and `onSurface` are unchanged. The container tiers were all
    // pure white before; they now form a real ramp. Dialogs, sheets, menus and
    // drawers are pinned back to `surface` in the component themes so this
    // change is not visible until each is migrated.
    surface: BrandPalette.white,
    onSurface: BrandPalette.ink900,

    surfaceContainerLowest: BrandPalette.white,
    surfaceContainerLow: BrandPalette.ink20,
    surfaceContainer: BrandPalette.ink30,
    surfaceContainerHigh: BrandPalette.ink60,
    surfaceContainerHighest: BrandPalette.ink40,

    surfaceDim: BrandPalette.ink50,
    surfaceBright: BrandPalette.white,

    // Previously equal to `onSurface` (#111111), which is why un-themed
    // secondary text rendered as primary ink.
    onSurfaceVariant: BrandPalette.ink550,

    inverseSurface: BrandPalette.ink900,
    onInverseSurface: BrandPalette.white,
    inversePrimary: BrandPalette.blue300,

    // ── Lines ────────────────────────────────────────────────────────────────
    // `outline` is unchanged (`stroke`). `outlineVariant` was pure black.
    outline: BrandPalette.ink100,
    outlineVariant: BrandPalette.ink120,

    shadow: BrandPalette.mediaBlack,
    scrim: BrandPalette.mediaBlack,

    // M3 tints elevated surfaces with this. The app's surfaces are flat by
    // design, so it is neutralised rather than left at `primary`.
    surfaceTint: Colors.transparent,
  );

  /// The dark scheme. Every value here is new — the app had no dark palette.
  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,

    // ── Brand ────────────────────────────────────────────────────────────────
    // Lifted from the brand `#2962FF`, which fails AA on a dark ground.
    // `onPrimary` is dark rather than white: white on a lifted indigo measures
    // about 2.6:1, whereas the dark ink clears 7:1.
    //
    // **`primary` is deliberately still the indigo, not the near-white CTA
    // fill.** 317 call sites outside the theme layer read `colorScheme.primary`
    // — filter chips, segmented controls, tab indicators, the nav bar's
    // selected label, progress spinners, unread badges, link text, the bookmark
    // glyph. Repointing this role to `#F2F2F5` would turn every one of them
    // white, which is the opposite of a restrained accent.
    //
    // The primary *action* fill lives in `SyncUpSemantics.ctaFill` and is wired
    // into the button themes only. See `button_themes.dart`.
    primary: BrandPalette.blue500,
    onPrimary: BrandPalette.graphite950,

    primaryContainer: BrandPalette.blue800,
    onPrimaryContainer: BrandPalette.blue200,

    secondary: BrandPalette.cyan300,
    onSecondary: BrandPalette.graphite950,
    secondaryContainer: BrandPalette.cyan800,
    onSecondaryContainer: BrandPalette.cyan300,

    tertiary: BrandPalette.violet400,
    onTertiary: BrandPalette.graphite950,
    tertiaryContainer: BrandPalette.violet900,
    onTertiaryContainer: BrandPalette.violet300,

    // ── Error ────────────────────────────────────────────────────────────────
    error: BrandPalette.red300,
    onError: BrandPalette.graphite950,
    errorContainer: BrandPalette.red900,
    onErrorContainer: BrandPalette.red300,

    // ── Surfaces ─────────────────────────────────────────────────────────────
    // Five tiers, so cards, controls and sheets separate by tone rather than by
    // the black shadows the light design uses (which are invisible on dark).
    //
    // Repointed from the blue-cast `slate*` ramp to the neutral graphite one:
    // the page drops to `#0A0A0C`, and `surfaceContainerLowest` now resolves to
    // the *inset* tier below the page rather than repeating the page itself,
    // which is what gives input wells and media letterboxes somewhere to sit.
    surface: BrandPalette.graphite950,
    onSurface: BrandPalette.graphiteInk100,

    surfaceContainerLowest: BrandPalette.graphite990,
    surfaceContainerLow: BrandPalette.graphite900,
    surfaceContainer: BrandPalette.graphite850,
    surfaceContainerHigh: BrandPalette.graphite800,
    surfaceContainerHighest: BrandPalette.graphite750,

    surfaceDim: BrandPalette.graphite990,
    surfaceBright: BrandPalette.graphite750,

    onSurfaceVariant: BrandPalette.graphiteInk300,

    inverseSurface: BrandPalette.graphiteInk100,
    onInverseSurface: BrandPalette.graphite950,
    inversePrimary: BrandPalette.blue600,

    // ── Lines ────────────────────────────────────────────────────────────────
    // `outline` is the perceptible boundary (input borders, focused edges) and
    // clears 3:1. `outlineVariant` is the quiet divider. In light these two are
    // nearly the same value; on a dark ground one value cannot do both jobs.
    //
    // **Accessibility override.** The Aperture spec assigns `#2A2A32`
    // ("default line") to this tier, but `outline` is what Flutter paints
    // around text fields, checkboxes and focused controls — boundaries that
    // convey state and therefore owe WCAG 1.4.11's 3:1. `#2A2A32` measures
    // ~1.6:1 on the page. `outline` is pinned to the interactive value instead;
    // `#2A2A32` and `#3A3A45` are still available as `lineDefault` /
    // `lineStrong` tokens for the decorative edges they were meant for.
    outline: BrandPalette.graphiteLine400,
    outlineVariant: BrandPalette.graphiteLine100,

    shadow: BrandPalette.mediaBlack,
    scrim: BrandPalette.mediaBlack,
    surfaceTint: Colors.transparent,
  );

  /// Strict black-and-white scheme for the profile surface. Pure `#000000`
  /// page, pure white primary, and a neutral (zero-chroma) grey ladder for the
  /// tiers in between. Every accent role resolves to white or grey so nothing
  /// on the profile can pick up a hue.
  static const ColorScheme mono = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF1F1F1F),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFE5E5E5),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF1A1A1A),
    onSecondaryContainer: Color(0xFFFFFFFF),
    tertiary: Color(0xFFD4D4D4),
    onTertiary: Color(0xFF000000),
    tertiaryContainer: Color(0xFF1A1A1A),
    onTertiaryContainer: Color(0xFFFFFFFF),
    // Errors keep their meaning, but in ink rather than a red slab.
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF000000),
    errorContainer: Color(0xFF1F1010),
    onErrorContainer: Color(0xFFFF8A8A),
    surface: Color(0xFF000000),
    onSurface: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF0A0A0A),
    surfaceContainer: Color(0xFF111111),
    surfaceContainerHigh: Color(0xFF171717),
    surfaceContainerHighest: Color(0xFF1F1F1F),
    surfaceDim: Color(0xFF000000),
    surfaceBright: Color(0xFF262626),
    onSurfaceVariant: Color(0xFFA3A3A3),
    inverseSurface: Color(0xFFFFFFFF),
    onInverseSurface: Color(0xFF000000),
    inversePrimary: Color(0xFF000000),
    outline: Color(0xFF5C5C5C),
    outlineVariant: Color(0xFF1F1F1F),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );
}
