import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';

import '../data/models/user_profile.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';
import 'skill_marks.dart';

class SkillCategoryBlock extends StatelessWidget {
  final String title;
  final List<String> values;

  /// The category's saved accent, or null when the user has not chosen one.
  ///
  /// Null renders the neutral treatment: secondary-ink title and a hairline
  /// chip edge. Categories used to be colour-coded from a fixed rainbow when
  /// nothing was saved, which put seven unrelated hues on one card for no
  /// reason a reader could recover. A colour now appears only when it is the
  /// user's own.
  final Color? accent;

  const SkillCategoryBlock({
    super.key,
    required this.title,
    required this.values,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final titleInk = accent ?? colors.onSurfaceVariant;
    // Each skill carries its own colour (its brand hue, or a stable one for
    // a practice) — see [skillMarkFor]. A saved category colour lives on the
    // heading only.
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: titleInk,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in values) SkillColorChip(label: value),
            ],
          ),
        ],
      ),
    );
  }
}

class TechnicalSkillRow extends StatelessWidget {
  final TechnicalSkill skill;

  const TechnicalSkillRow({
    super.key,
    required this.skill,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final color = Color(skill.colorValue);
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            skill.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${skill.level} • ${skill.experience}',
            style: TextStyle(
              fontSize: 11,
              color: tokens.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: skill.progress,
              minHeight: 4,
              backgroundColor: colors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class LanguageRow extends StatelessWidget {
  final LanguageEntry language;

  const LanguageRow({
    super.key,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final t = ProfileSurfaceTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  language.name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ),
              Text(
                language.level,
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: language.progress,
              minHeight: 3,
              backgroundColor: t.raisedFill,
              // A proficiency bar states a level, it is not an action: the
              // secondary ink on the hairline track, so a full bar is a quiet
              // rule rather than a bright white stripe across the card.
              valueColor:
                  AlwaysStoppedAnimation<Color>(colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class ProjectTile extends StatelessWidget {
  final ProjectEntry? project;
  final bool isAddTile;

  /// Tap handler for the add tile. Handled inside the tile so the press shows
  /// ink on the tile itself rather than nothing at all.
  final VoidCallback? onTap;

  const ProjectTile({
    super.key,
    this.project,
    this.isAddTile = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    if (isAddTile) {
      // The upload/drop-zone treatment, shared with the resume zones: a dashed
      // interactive-line edge on the upload fill, with the "+" and label in
      // `controlInk`. Dashed says "add something here"; the edge and the
      // near-white glyph say it is tappable; neither needs to be blue.
      return DottedBorder(
        borderType: BorderType.RRect,
        radius: const Radius.circular(ProfileSurfaceTokens.nestedRadius),
        color: tokens.uploadZoneBorder,
        strokeWidth: 1.5,
        dashPattern: const [6, 4],
        child: Material(
          color: tokens.uploadZoneFill,
          borderRadius:
              BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius:
                BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: tokens.controlInk),
                  const SizedBox(height: 6),
                  Text(
                    'Add Proof of Work',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.controlInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // A saved project on the edit screen: its cover (or the tonal
    // placeholder) under the fixed media scrim, captioned in the media ink,
    // with a small edit glyph — the same tile the profile view draws, so the
    // edit surface shows what the profile shows.
    final coverUrl = project?.coverUrl;
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
          size: 26,
          color: colors.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl != null && coverUrl.isNotEmpty)
            Image.network(
              coverUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            )
          else
            placeholder,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  tokens.mediaSurface.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Icon(
              Icons.edit_outlined,
              size: 15,
              color: tokens.onMediaSurface.withValues(alpha: 0.85),
              semanticLabel: 'Edit',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(11),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onMediaSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    project!.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onMediaSurface.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
