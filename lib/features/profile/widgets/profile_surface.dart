import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/glass_tokens.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../shared/widgets/glass/glass.dart';

/// Which rung of the profile's surface ladder a pane sits on. See
/// [ProfileSurfaceTokens] for what each one means.
enum ProfileSurfaceTier { card, raised, inset, chip, control }

extension on ProfileSurfaceTokens {
  GlassSpec specFor(ProfileSurfaceTier tier) => switch (tier) {
        ProfileSurfaceTier.card => card,
        ProfileSurfaceTier.raised => raised,
        ProfileSurfaceTier.inset => inset,
        ProfileSurfaceTier.chip => chip,
        ProfileSurfaceTier.control => control,
      };

  GlassSpec pressedFor(ProfileSurfaceTier tier) => switch (tier) {
        ProfileSurfaceTier.card => cardPressed,
        ProfileSurfaceTier.raised => raisedPressed,
        ProfileSurfaceTier.inset => inset,
        ProfileSurfaceTier.chip => chipPressed,
        ProfileSurfaceTier.control => controlPressed,
      };

  double radiusFor(ProfileSurfaceTier tier) => switch (tier) {
        ProfileSurfaceTier.card => ProfileSurfaceTokens.cardRadius,
        ProfileSurfaceTier.raised => ProfileSurfaceTokens.nestedRadius,
        ProfileSurfaceTier.inset => ProfileSurfaceTokens.nestedRadius,
        ProfileSurfaceTier.chip => ProfileSurfaceTokens.chipRadius,
        ProfileSurfaceTier.control => ProfileSurfaceTokens.nestedRadius,
      };
}

/// One pane of the profile's glass: the card every section sits in, the row
/// nested inside it, a well, a chip or a control — one widget, one tier
/// argument, so no section spells out its own `BoxDecoration`.
///
/// Purely presentational unless [onTap] is given, in which case the whole pane
/// becomes a button (semantics, keyboard activation, focus ring) and dips to
/// the tier's pressed spec — the same [GlassPressable] contract every glass
/// control in the app follows.
class ProfileSurface extends StatelessWidget {
  const ProfileSurface({
    super.key,
    required this.child,
    this.tier = ProfileSurfaceTier.card,
    this.padding,
    this.margin,
    this.radius,
    this.onTap,
    this.clip = false,
    this.width,
  });

  final Widget child;
  final ProfileSurfaceTier tier;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Overrides the tier's corner radius.
  final double? radius;

  /// Makes the pane tappable.
  final VoidCallback? onTap;

  /// Clips [child] to the pane's corners — for media that would otherwise
  /// paint square over them.
  final bool clip;

  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = ProfileSurfaceTokens.of(context);
    final rest = t.specFor(tier);
    final pressed = t.pressedFor(tier);
    final r = BorderRadius.circular(radius ?? t.radiusFor(tier));

    Widget body =
        padding == null ? child : Padding(padding: padding!, child: child);
    if (clip) body = ClipRRect(borderRadius: r, child: body);
    if (width != null) body = SizedBox(width: width, child: body);

    Widget pane;
    if (onTap == null) {
      pane = GlassSurface(spec: rest, borderRadius: r, child: body);
    } else {
      pane = GlassPressable(
        onPressed: onTap,
        borderRadius: r,
        pressedScale: 0.985,
        builder: (context, s) => GlassSurface(
          spec: GlassSpec.lerp(rest, pressed, math.max(s.press, s.hover * 0.5)),
          borderRadius: r,
          child: body,
        ),
      );
    }
    return margin == null ? pane : Padding(padding: margin!, child: pane);
  }
}

/// A compact glass pill for chrome drawn **on the cover** — the Share pill, the
/// CV export's Copy Link.
///
/// It is the pane [GlassIconButton] draws (the kit's charcoal secondary glass,
/// translucent, with a lit rim and a short drop), so the Back disc and the
/// Share pill beside it are one control family, legible over a bright photo
/// (the fill) and over a near-black cover (the rim). Content-scale actions on
/// the page itself use `AppButton` instead; this exists only because a cover
/// control needs a label *and* the fully round ends of the disc next to it.
class ProfileGlassPill extends StatelessWidget {
  const ProfileGlassPill({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 44,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTokens.of(context);
    final ink = context.colorScheme.onSurface;
    final radius = BorderRadius.circular(height / 2);

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: ink),
            const SizedBox(width: 7),
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
    );

    final pill = SizedBox(
      height: height,
      child: GlassPressable(
        onPressed: onTap,
        borderRadius: radius,
        pressedScale: 0.97,
        builder: (context, s) {
          final lit = GlassSpec.lerp(
              glass.secondaryDisabled, glass.secondary, s.enabled);
          return GlassSurface(
            spec: GlassSpec.lerp(lit, glass.secondaryPressed, s.press),
            borderRadius: radius,
            child: Opacity(opacity: 0.55 + 0.45 * s.enabled, child: content),
          );
        },
      ),
    );

    if (semanticLabel == null) return pill;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: pill,
    );
  }
}

/// A small round glass control — a section header's add / edit — drawn at
/// [size] inside a [hitSize] target.
///
/// [GlassIconButton] is the 44pt version of this; content-scale controls are
/// 32pt and would look like buttons on a form at 44, so this keeps the visual
/// small and the target honest.
class ProfileGlassDisc extends StatelessWidget {
  const ProfileGlassDisc({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.size = 32,
    this.hitSize = 44,
    this.iconSize = 16,
    this.iconColor,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final double size;
  final double hitSize;
  final double iconSize;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final t = ProfileSurfaceTokens.of(context);
    final tokens = context.tokensOrDefault;
    final radius = BorderRadius.circular(hitSize / 2);
    final ink = iconColor ?? tokens.controlInk;
    return SizedBox.square(
      dimension: hitSize,
      child: GlassPressable(
        onPressed: onTap,
        borderRadius: radius,
        pressedScale: 0.9,
        builder: (context, s) => Center(
          child: SizedBox.square(
            dimension: size,
            child: GlassSurface(
              spec: GlassSpec.lerp(t.control, t.controlPressed, s.press),
              borderRadius: BorderRadius.circular(size / 2),
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: ink.withValues(alpha: 0.5 + 0.5 * s.enabled),
                  semanticLabel: semanticLabel,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small tonal tile carrying a glyph — a section heading's icon, a file's
/// type, a sheet heading's icon. Tone only, no rim: it labels, it is not a
/// control, so it must not look like one.
class ProfileGlyphTile extends StatelessWidget {
  const ProfileGlyphTile({
    super.key,
    required this.icon,
    this.size = 28,
    this.iconSize = 15,
    this.color,
    this.fill,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  /// Overrides the glyph ink (default `iconInk`).
  final Color? color;

  /// Overrides the tile tone (a saved accent's tint).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final t = ProfileSurfaceTokens.of(context);
    final tokens = context.tokensOrDefault;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill ?? t.raisedFill,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: Center(
            child: Icon(icon, size: iconSize, color: color ?? tokens.iconInk),
          ),
        ),
      ),
    );
  }
}

/// A 1px separator in the profile's hairline tone.
class ProfileHairline extends StatelessWidget {
  const ProfileHairline({super.key, this.strong = false, this.indent = 0});

  final bool strong;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final t = ProfileSurfaceTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: strong ? t.hairlineStrong : t.hairline),
      ),
    );
  }
}
