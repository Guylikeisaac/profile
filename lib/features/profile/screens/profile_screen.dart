import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_manager.dart';
// INTERIM: the edit form is still the legacy screen, now fed from self-loaded
// data instead of args carried by the caller. Replace with
// features/profile/screens/edit_profile_screen.dart in the next step.
import '../../../screens/profile/edit_profile.dart';
import '../data/models/user_profile.dart';
import '../providers/profile_provider.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/theme_context_ext.dart';

/// Self-loading profile screen. Takes no constructor args — it fetches the
/// current user's profile via [myProfileProvider]. This replaces the old
/// data-carrying `ProfilePage(coverImageUrl: ..., ...)` push.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokensOrDefault;
    final async = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: tokens.inputFill,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          async.maybeWhen(
            data: (p) => TextButton(
              onPressed: () => _openEdit(context, p),
              child: const Text('Edit'),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorView(
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
        data: (profile) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myProfileProvider),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _ProfileHeader(profile: profile),
              if (profile.completionPercent != null &&
                  profile.completionPercent! < 100)
                _CompletionBanner(
                  percent: profile.completionPercent!,
                  onComplete: () => _openEdit(context, profile),
                ),
              const SizedBox(height: 8),
              _Section(
                title: 'Experience',
                emptyLabel: 'Add your work experience',
                items: profile.experiences,
              ),
              _Section(
                title: 'Education',
                emptyLabel: 'Add your education',
                items: profile.educations,
              ),
              _SkillsSection(skills: profile.skills),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _openEdit(BuildContext context, UserProfile p) {
    final me = AuthManager().currentUser;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditProfilePage(
          username: p.userId,
          fullName: p.name,
          mobileNumber: me?.phone ?? '',
          email: me?.email ?? '',
          jobPosition: p.title,
          location: p.location ?? '',
          tagline: '',
          profileImagePath: p.profilePic,
          coverImagePath: p.banner,
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final colors = context.colorScheme;
    final banner = profile.banner ?? '';
    final avatar = profile.profilePic;

    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 146,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 110,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tokens.heroSurfaceEnd, colors.primary],
                    ),
                    image: banner.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(banner),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 74,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primaryContainer,
                      border: Border.all(color: colors.surface, width: 3),
                      image: avatar.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(avatar),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: avatar.isEmpty
                        ? Icon(Icons.person, color: colors.primary, size: 34)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name.isEmpty ? 'Your name' : profile.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                if (profile.title.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.title,
                    style: TextStyle(fontSize: 14, color: colors.onSurface),
                  ),
                ],
                if ((profile.location ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 15, color: colors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        profile.location!,
                        style: TextStyle(
                            fontSize: 13, color: colors.onSurfaceVariant),
                      ),
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

class _CompletionBanner extends StatelessWidget {
  final int percent;
  final VoidCallback onComplete;

  const _CompletionBanner({required this.percent, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Profile completion',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (percent.clamp(0, 100)) / 100,
              minHeight: 6,
              backgroundColor: colors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: onComplete,
              child: const Text('Complete your profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final List<ProfileEntry> items;

  const _Section({
    required this.title,
    required this.emptyLabel,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              emptyLabel,
              style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
            )
          else
            for (final item in items) ...[
              _EntryRow(entry: item),
              if (item != items.last) const Divider(height: 20),
            ],
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final ProfileEntry entry;

  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.title.isNotEmpty)
          Text(
            entry.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        if (entry.subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            entry.subtitle,
            style: TextStyle(fontSize: 13.5, color: colors.onSurface),
          ),
        ],
        if (entry.meta != null) ...[
          const SizedBox(height: 2),
          Text(
            entry.meta!,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _SkillsSection extends StatelessWidget {
  final List<String> skills;

  const _SkillsSection({required this.skills});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Skills',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (skills.isEmpty)
            Text(
              'Add your key skills',
              style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final skill in skills)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: tokens.inputFill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.outline),
                    ),
                    child: Text(
                      skill,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your profile",
              style: TextStyle(fontSize: 15, color: colors.onSurface),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
