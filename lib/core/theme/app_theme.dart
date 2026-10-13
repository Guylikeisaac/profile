import 'package:flutter/material.dart';

import 'app_typography.dart';
import 'brand_palette.dart';
import 'button_themes.dart';
import 'color_schemes.dart';
import 'control_themes.dart';
import 'input_theme.dart';
import 'navigation_themes.dart';
import 'semantic_tokens.dart';
import 'surface_themes.dart';

/// The app's themes.
///
/// This file is **assembly only** — it composes a [ColorScheme], the type scale
/// and the component themes, and installs [SyncUpSemantics] as a theme
/// extension. It contains no colour decisions of its own; those live in
/// `brand_palette.dart`, `color_schemes.dart` and `semantic_tokens.dart`.
///
/// ```dart
/// MaterialApp.router(
///   theme: AppTheme.light,
///   darkTheme: AppTheme.dark,
///   themeMode: choice.materialMode,
/// );
/// ```
///
/// ## Light and dark are not symmetric, on purpose
///
/// A few values are set in dark but deliberately left to the framework in
/// light. Light mode already renders correctly and the migration's first rule is
/// that it must not change; dark had no values at all and needs deliberate ones.
/// Each asymmetry is commented where it occurs.
abstract final class AppTheme {
  /// The light theme. Preserves the app's shipped appearance.
  static ThemeData get light => _build(
        SyncUpColorSchemes.light,
        SyncUpSemantics.light,
      );

  /// The dark theme.
  static ThemeData get dark => _build(
        SyncUpColorSchemes.dark,
        SyncUpSemantics.dark,
      );

  /// The profile's strict monochrome theme: a pure-black page, white ink and
  /// a neutral grey ramp — no brand hue anywhere. Forced on every profile
  /// rendering regardless of the app's theme mode. See
  /// [SyncUpColorSchemes.mono] and [SyncUpSemantics.mono].
  static ThemeData get profileMono => _build(
        SyncUpColorSchemes.mono,
        SyncUpSemantics.mono,
      );

  static ThemeData _build(ColorScheme colors, SyncUpSemantics tokens) {
    final isLight = colors.brightness == Brightness.light;
    final ink = AppSurfaceThemes.inkColors(colors, tokens);

    return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      colorScheme: colors,
      fontFamily: AppTypography.fontFamily,

      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,

      // Flat surfaces throughout; M3's elevation tint would add a brand cast
      // the design does not have.
      applyElevationOverlayColor: false,

      textTheme: AppTypography.textTheme(colors, tokens),

      // ── Icons ────────────────────────────────────────────────────────────
      // PIN (light): the framework's legacy `black87` default, which is what
      // every un-migrated `Icon()` without an explicit colour resolves to
      // today. Retire once icon colours migrate to `onSurface`.
      iconTheme: IconThemeData(
        color: isLight ? BrandPalette.inkIconLegacy : colors.onSurface,
      ),

      // ── Ink response ─────────────────────────────────────────────────────
      // Null in light so the framework's existing splashes stand unchanged.
      // In dark the light-derived defaults are almost imperceptible.
      splashColor: ink.splash,
      highlightColor: ink.highlight,
      focusColor: ink.focus,
      hoverColor: ink.hover,

      // ── Components ───────────────────────────────────────────────────────
      // These take tokens as well as the scheme: the primary action fill is
      // `tokens.ctaFill`, and the outlined button's chrome is
      // `tokens.controlInk` / `controlOutline`, not `colors.primary`. See
      // `button_themes.dart`.
      elevatedButtonTheme: AppButtonThemes.elevated(colors, tokens),
      filledButtonTheme: AppButtonThemes.filled(colors, tokens),
      outlinedButtonTheme: AppButtonThemes.outlined(colors, tokens),
      textButtonTheme: AppButtonThemes.text(colors),
      iconButtonTheme: AppButtonThemes.icon(colors),

      inputDecorationTheme: AppInputTheme.decoration(colors, tokens),
      textSelectionTheme: AppInputTheme.selection(colors),

      cardTheme: AppSurfaceThemes.card(colors),
      dialogTheme: AppSurfaceThemes.dialog(colors),
      bottomSheetTheme: AppSurfaceThemes.bottomSheet(colors),
      drawerTheme: AppSurfaceThemes.drawer(colors),
      popupMenuTheme: AppSurfaceThemes.popupMenu(colors),
      listTileTheme: AppSurfaceThemes.listTile(colors),
      dividerTheme: AppSurfaceThemes.divider(colors),
      snackBarTheme: AppSurfaceThemes.snackBar(colors),
      tooltipTheme: AppSurfaceThemes.tooltip(colors),

      switchTheme: AppControlThemes.switchTheme(colors),
      checkboxTheme: AppControlThemes.checkbox(colors),
      radioTheme: AppControlThemes.radio(colors),
      sliderTheme: AppControlThemes.slider(colors),
      progressIndicatorTheme: AppControlThemes.progress(colors),
      chipTheme: AppControlThemes.chip(colors, tokens),
      tabBarTheme: AppControlThemes.tabBar(colors, tokens),

      appBarTheme: AppNavigationThemes.appBar(colors),
      floatingActionButtonTheme: AppNavigationThemes.fab(colors),
      navigationBarTheme: AppNavigationThemes.navigationBar(colors),
      bottomNavigationBarTheme: AppNavigationThemes.bottomNavigationBar(colors),

      // ── Semantic tokens ──────────────────────────────────────────────────
      // Read via `context.tokens` (theme_context_ext.dart).
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }
}
