import 'package:flutter/material.dart';

import '../data/models/user_profile.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/helpers/work_link_url.dart' show readableBrandColor;
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/semantic_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../shared/widgets/app_chip.dart';
import 'profile_surface.dart';

/// Parses a `#RRGGBB` / `#AARRGGBB` accent hex into a [Color], or null when it's
/// absent/unparseable. Shared so a record's persisted accent colour is
/// reflected on the experience cards in both the view and edit screens.
Color? profileAccentFromHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// The accent a saved [hex] shows as on the profile itself: none.
///
/// The profile renders strictly black and white (`AppTheme.profileMono`), so
/// a saved accent stays in the data — the web app and the colour pickers still
/// use it — but every profile card draws its neutral treatment.
Color? profileDisplayAccent(String? hex) => null;

/// Resolves the accent colour for a skill category: the user's saved colour
/// (`skillCategoryAccentColors`, matched case-insensitively on the category
/// name) when present, else **null** — the neutral treatment.
///
/// There used to be a fixed seven-colour fallback palette hashed from the
/// category name, so a profile with no saved colours still showed a rainbow of
/// category headings that meant nothing. A colour on a category now means the
/// user chose it. Shared by the profile Skills section and the edit sheet so
/// both agree.
Color? skillCategoryColor(String category, Map<String, String> saved) {
  final key = category.trim().toUpperCase();
  return profileAccentFromHex(saved[key]);
}

/// The three legible tints an Education card paints from a base accent, so a
/// pastel choice themes the card without hurting contrast. Shared by the outer
/// profile card ([EducationCard]) and the in-sheet management row so both render
/// the same colour for a given entry:
///   • [card] — the card background
///   • [icon] — the grad-cap chip / grade-badge fill
///   • [fg]   — readable same-hue foreground for the icon + grade text
///
/// **[brightness] is not optional on purpose.** The recipe used to be a single
/// light-mode one: a lightness-0.94 card, i.e. an almost-white lavender slab,
/// painted unconditionally. On dark that put the card's `onSurface` title —
/// near-white — on a near-white ground, which is why Education was the one
/// unreadable card on the profile. The dark recipe mirrors it about the middle
/// of the ramp: a near-black card, a deep tonal chip, and a *light* same-hue
/// foreground.
({Color card, Color icon, Color fg}) educationAccentTints(
  Color base, {
  required Brightness brightness,
}) {
  final hsl = HSLColor.fromColor(base);
  final sat = hsl.saturation.clamp(0.5, 0.9);
  if (brightness == Brightness.dark) {
    return (
      // Desaturated to a whisper, so this lands on the graphite ramp beside
      // the other profile cards (~`surfaceContainerLow`) and reads as a raised
      // neutral surface rather than a tinted one, whatever hue was saved.
      card: hsl
          .withLightness(0.075)
          .withSaturation(sat.clamp(0.0, 0.10))
          .toColor(),
      // The accent survives here: a restrained dark tonal chip / grade badge…
      icon: hsl
          .withLightness(0.22)
          .withSaturation(sat.clamp(0.0, 0.45))
          .toColor(),
      // …carrying light same-hue ink, the inverse of the light recipe's dark ink.
      fg: hsl.withLightness(0.80).withSaturation(sat).toColor(),
    );
  }
  return (
    // Slightly deeper than before so the colour reads as intentional (not a
    // washed-out pastel) while keeping dark text legible on the card.
    card: hsl.withLightness(0.94).withSaturation(sat.clamp(0.0, 0.6)).toColor(),
    icon: hsl.withLightness(0.84).withSaturation(sat).toColor(),
    fg: hsl.withLightness(0.40).withSaturation(sat).toColor(),
  );
}

/// The Education card's tints when the entry has **no** saved accent: a plain
/// tonal step off the section card, a neutral glyph tile and secondary ink.
///
/// This replaces a hard-coded purple default. An unset colour used to render
/// as a lavender tile on every education entry, which on the dark profile was
/// one more purple mark competing with the headings; unset now reads as unset.
({Color card, Color icon, Color fg}) educationNeutralTints(
  ColorScheme colors,
  SyncUpSemantics tokens,
) {
  return (
    card: colors.surfaceContainerLow,
    icon: tokens.iconTile,
    fg: tokens.iconInk,
  );
}

/// Experience entry: company logo, title and company, duration badge,
/// bullets.
///
/// [accent] is the entry's **saved** colour, or null. Null renders the
/// neutral rail and secondary-ink company line; entries used to be
/// colour-coded by order when nothing was saved, which put an indigo, a blue
/// and an amber rail on three consecutive roles for no reason a reader could
/// recover.
class EntryCard extends StatelessWidget {
  final ProfileEntry entry;
  final Color? accent;
  final Color badgeBackground;
  final Color badgeForeground;

  const EntryCard({
    super.key,
    required this.entry,
    required this.accent,
    required this.badgeBackground,
    required this.badgeForeground,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final companyInk = accent ?? colors.onSurfaceVariant;
    // The rail is a SEPARATE straight bar (a Row child), not the container's
    // left border. A left BorderSide on a rounded container traces the corner
    // radius and reads as a curved "(" bracket — this keeps it dead straight.
    //
    // No fill of its own: the entry sits directly on the section card's
    // glass. It used to paint `surface`, which on the translucent card would
    // punch a near-black block through it.
    //
    // Drawn as a positioned child that stretches to the content's height, not
    // with `IntrinsicHeight`: that asks every descendant for a dry layout, and
    // the shared chips (a `LayoutBuilder` inside) cannot give one.
    // No rail: the company's logo leads the entry instead.
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompanyLogo(name: entry.subtitle, website: entry.companyWebsite),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: companyInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (entry.trailingBadge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: badgeBackground,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              entry.trailingBadge!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: badgeForeground,
                              ),
                            ),
                          ),
                        if (entry.meta != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            entry.meta!,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: tokens.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                if (entry.bullets.isNotEmpty) const SizedBox(height: 8),
                for (var b = 0; b < entry.bullets.length; b++) ...[
                  if (b > 0) const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.bullets[b],
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurface,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // Hands-on skills for this role. Rendered on both the self
                // and public views — the read payload is identical, and
                // there's nothing owner-only about them.
                if (entry.usedSkills.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final skill in entry.usedSkills)
                        UsedSkillChip(label: skill.name, accent: accent),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single "skill used in this role" chip.
///
/// Neutral: the app's meta chip, the same label the Skills section uses. When
/// the entry has a saved accent the chip takes a faint wash of it and the
/// accent ink, so the skills read as part of that role — the same small-radius
/// shape either way, since a skill is a label, not a status.
class UsedSkillChip extends StatelessWidget {
  final String label;
  final Color? accent;

  const UsedSkillChip({
    super.key,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent;
    if (a == null) return AppChip(label: label);
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: a.withValues(alpha: 0.12),
        borderRadius: AppRadii.smallAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: readableBrandColor(a, context.colorScheme.surfaceContainerLow),
        ),
      ),
    );
  }
}

/// Education entry: tonal card, grad-cap chip, inline date + badge.
class EducationCard extends StatelessWidget {
  final ProfileEntry entry;

  const EducationCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final date =
        (entry.meta ?? '').replaceAll(' – ', '–').replaceAll(' - ', '–');
    // Drive the card off the saved accent so the chosen colour is meaningful,
    // using the shared derivation so the in-sheet row matches exactly. No
    // saved colour → the neutral card.
    final base = profileDisplayAccent(entry.accentColorHex);
    final tints = base == null
        ? educationNeutralTints(colors, tokens)
        : educationAccentTints(
            base,
            brightness: Theme.of(context).brightness,
          );
    final iconBg = tints.icon;
    final fg = tints.fg;
    // The row is the raised pane one step up from the section card; the saved
    // accent survives on the glyph tile and the grade badge, where it is a
    // detail rather than a slab.
    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.school_outlined, size: 18, color: fg),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (date.isNotEmpty)
                      Text(
                        date,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textTertiary,
                        ),
                      ),
                    if (date.isNotEmpty && entry.trailingBadge != null)
                      const SizedBox(width: 8),
                    if (entry.trailingBadge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: AppRadii.smallAll,
                        ),
                        child: Text(
                          entry.trailingBadge!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A company's logo, bare (no tile behind it), looked up from its website's
/// domain; the company's initial on a dark tile when there is no website or
/// the logo cannot be fetched.
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({
    super.key,
    required this.name,
    this.website,
    this.size = 40,
  });

  final String name;
  final String? website;
  final double size;

  /// The bare host of [website] ("https://www.razorpay.com/x" → razorpay.com).
  static String? domainOf(String? website) {
    final raw = (website ?? '').trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    final host = uri?.host.toLowerCase() ?? '';
    if (host.isEmpty || !host.contains('.')) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final radius = BorderRadius.circular(size * 0.26);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.08),
        borderRadius: radius,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: colors.onSurface,
        ),
      ),
    );
    final domain = domainOf(website);
    if (domain == null) return ExcludeSemantics(child: fallback);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            'https://www.google.com/s2/favicons?domain=$domain&sz=128',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            // The logo service sends no CORS header; on the web this lets the
            // browser draw it as a plain image element instead of failing.
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (_, __, ___) => fallback,
          ),
        ),
      ),
    );
  }
}
