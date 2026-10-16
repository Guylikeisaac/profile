import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/network/data/connection_repository.dart';
import 'features/network/providers/network_providers.dart';
import 'features/post/data/models/post_models.dart';
import 'features/post/data/post_repository.dart';
import 'features/post/providers/post_providers.dart';
import 'features/profile/data/activity_repository.dart';
import 'features/profile/providers/activity_provider.dart';
import 'features/profile/providers/certifications_provider.dart';
import 'features/profile/providers/profile_provider.dart';
import 'features/profile/providers/references_provider.dart';
import 'features/profile/screens/profile_view_screen.dart';
import 'features/readiness_sprint/providers/sprint_providers.dart';
import 'features/resume/providers/profile_resume_provider.dart';
import 'preview/preview_profile_data.dart';

/// Design preview: the profile screen alone, on sample data, no sign-in.
///
/// Two views of the same profile, switched with the pill at the bottom:
///  * `/`       — the owner's own view (Edit Profile, connections count…)
///  * `/public` — what anyone else sees (Connect, Message, mutuals)
///
/// `flutter build web -t lib/main_profile_preview.dart`. Never shipped — the
/// real entry point is `main.dart`.
void main() {
  runApp(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(PreviewProfileRepository()),
        selfConnectionCountProvider.overrideWith((ref) async => 1847),
        myCertificationsProvider
            .overrideWith((ref) async => PreviewData.certifications),
        myReferencesProvider
            .overrideWith((ref) async => PreviewData.references),
        incomingReferenceRequestsProvider.overrideWith((ref) async => []),
        profileResumeProvider.overrideWith((ref) async => PreviewData.resume),
        sprintPendingStatusProvider.overrideWith((ref) async => null),
        postRepositoryProvider.overrideWithValue(_EmptyPosts()),
        activityRepositoryProvider.overrideWithValue(_EmptyActivity()),
        connectionRepositoryProvider.overrideWithValue(_PreviewConnections()),
      ],
      child: MaterialApp.router(
        title: 'SyncUp Profile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: _router,
        // The page leaves room at the bottom for the floating switch, so the
        // last card is never hidden behind it.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return Stack(
            children: [
              MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(bottom: mq.padding.bottom + 64),
                ),
                child: child!,
              ),
              const _ViewSwitch(),
            ],
          );
        },
      ),
    ),
  );
}

/// The handle the public view opens — the sample profile's own.
const _publicHandle = 'arjun-mehta';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const ProfileViewScreen.self(),
    ),
    GoRoute(
      path: '/public',
      builder: (_, __) => const ProfileViewScreen.public(userId: _publicHandle),
    ),
  ],
);

/// A small floating "Owner · Public" switch, pinned to the bottom. Preview
/// only — the real app reaches the public view from someone else's profile.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _router.routeInformationProvider,
      builder: (context, _) {
        final isPublic =
            _router.routeInformationProvider.value.uri.path == '/public';
        return Positioned(
          left: 0,
          right: 0,
          bottom: 20 + MediaQuery.paddingOf(context).bottom,
          child: Center(
            child: Material(
              color: const Color(0xF0161616),
              shape: StadiumBorder(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              ),
              elevation: 8,
              shadowColor: Colors.black,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SwitchSegment(
                      label: 'Owner view',
                      selected: !isPublic,
                      onTap: () => _router.go('/'),
                    ),
                    _SwitchSegment(
                      label: 'Public view',
                      selected: isPublic,
                      onTap: () => _router.go('/public'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SwitchSegment extends StatelessWidget {
  const _SwitchSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: selected ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: ShapeDecoration(
            color: selected ? Colors.white : Colors.transparent,
            shape: const StadiumBorder(),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// Connections as a visitor sees them: not yet connected, a handful of
/// mutuals, and Connect / Withdraw that just succeed (nothing is sent).
class _PreviewConnections implements ConnectionRepository {
  @override
  Future<PublicConnectState> getConnectionState(String peerAuthUuid) async =>
      const PublicConnectState(PublicConnectKind.none);

  @override
  Future<MutualConnections> getMutuals(String userId) async =>
      MutualConnections(count: 12, sample: PreviewData.mutualSample);

  @override
  Future<String?> sendConnection(String receiverId) async => 'preview';

  @override
  Future<void> withdrawConnection(String receiverId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(UnsupportedError('preview'));
}

/// No posts — the preview has no session to fetch them with.
class _EmptyPosts implements PostRepository {
  @override
  Future<PostResponse> getUserPosts({
    required String userId,
    int page = 1,
    int limit = 10,
  }) async =>
      PreviewData.posts();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(UnsupportedError('preview'));
}

/// No activity — as above.
class _EmptyActivity implements ActivityRepository {
  @override
  Future<ActivityResponse> loadUserActivities({
    required String userUuid,
    required int page,
    int limit = 10,
    String? type,
  }) async =>
      ActivityResponse.fromJson(const {'activities': []});

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(UnsupportedError('preview'));
}
