import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/glass/glass.dart';
import 'profile_entry_cards.dart' show profileAccentFromHex;
import 'profile_surface.dart';

/// The Edit Profile screen's bar: the glass Back disc every glass page shares,
/// the title, and Save as the screen's primary action — the app's compact
/// primary button, which keeps itself lit with a spinner while the save is in
/// flight.
class EditProfileAppBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onSave;
  final bool isSaving;

  const EditProfileAppBar({
    super.key,
    required this.onBack,
    required this.onSave,
    required this.isSaving,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          GlassIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: 'Back',
            onPressed: onBack,
            iconSize: 21,
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Edit Profile',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
          AppButton.primary(
            label: 'Save',
            onPressed: onSave,
            loading: isSaving,
            expand: false,
            size: AppButtonSize.compact,
          ),
        ],
      ),
    );
  }
}

/// The Edit Profile screen's header: the cover band with its Edit Cover
/// control, and the avatar riding its lower edge with the change-photo badge.
///
/// It is the profile hero's cover in miniature, so the two agree: the same
/// neutral graphite falloff when nothing is saved (it used to fall back to the
/// indigo hero slab), the same darkened tint of a saved cover colour, the photo
/// laid over that with an error fallback, the avatar cut out by a
/// canvas-coloured ring, and the cover's controls on the same charcoal glass.
class ProfileCoverHeader extends StatelessWidget {
  final String bannerUrl;

  /// Saved solid cover colour hex (`#RRGGBB`) — shown when there's no photo.
  final String? bannerColor;
  final String avatarUrl;

  /// The account's name, for the initials fallback when there is no photo.
  final String name;
  final VoidCallback? onEditCover;
  final VoidCallback? onEditAvatar;

  const ProfileCoverHeader({
    super.key,
    required this.bannerUrl,
    this.bannerColor,
    required this.avatarUrl,
    this.name = '',
    this.onEditCover,
    this.onEditAvatar,
  });

  static const double _coverHeight = 128;
  static const double _avatarSize = 84;
  static const double _ring = 4;
  static const double _badgeSize = 28;
  static const double _badgeHit = 44;

  /// A saved colour pushed dark (the hero's recipe), else the neutral pair.
  List<Color> _coverColors(ProfileSurfaceTokens t) {
    final base = profileAccentFromHex(bannerColor);
    if (base == null) return [t.coverTop, t.coverBottom];
    final hsl = HSLColor.fromColor(base);
    final sat = hsl.saturation.clamp(0.35, 0.85);
    return [
      hsl.withLightness(0.30).withSaturation(sat).toColor(),
      hsl.withLightness(0.16).withSaturation(sat).toColor(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ProfileSurfaceTokens.of(context);
    final tokens = context.tokensOrDefault;
    final photo = cachedImageProvider(bannerUrl);
    const avatarTop = _coverHeight - _avatarSize / 2;
    const overhang = (_badgeHit - _badgeSize) / 2;

    return SizedBox(
      height: avatarTop + _avatarSize + overhang + 4,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _coverHeight,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _coverColors(t),
                      ),
                    ),
                  ),
                  if (photo != null)
                    Image(
                      image: photo,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  // The cover eases into the page, as the hero's does.
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: 0.4,
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              t.coverFade.withValues(alpha: 0),
                              t.coverFade.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: ProfileGlassPill(
                icon: Icons.photo_camera_outlined,
                label: 'Edit Cover',
                height: 40,
                onTap: onEditCover,
              ),
            ),
          ),
          Positioned(
            top: avatarTop - overhang,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox.square(
                dimension: _avatarSize + overhang * 2,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: _avatarSize,
                      height: _avatarSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.avatarRing,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.avatarRingEdge),
                        boxShadow: t.avatarShadow,
                      ),
                      child: AppUserAvatar(
                        name: name,
                        avatarUrl: avatarUrl,
                        size: _avatarSize - _ring * 2,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Semantics(
                        button: true,
                        enabled: onEditAvatar != null,
                        label: 'Change profile photo',
                        excludeSemantics: true,
                        onTap: onEditAvatar,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: onEditAvatar,
                          child: SizedBox.square(
                            dimension: _badgeHit,
                            child: Center(
                              child: Container(
                                width: _badgeSize,
                                height: _badgeSize,
                                decoration: BoxDecoration(
                                  color: tokens.ctaFill,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: t.avatarRing, width: 2.5),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
