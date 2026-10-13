import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
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
        myReferencesProvider.overrideWith((ref) async => PreviewData.references),
        incomingReferenceRequestsProvider.overrideWith((ref) async => []),
        profileResumeProvider.overrideWith((ref) async => PreviewData.resume),
        sprintPendingStatusProvider.overrideWith((ref) async => null),
        postRepositoryProvider.overrideWithValue(_EmptyPosts()),
        activityRepositoryProvider.overrideWithValue(_EmptyActivity()),
      ],
      child: MaterialApp.router(
        title: 'SyncUp Profile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const ProfileViewScreen.self(),
            ),
          ],
        ),
      ),
    ),
  );
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
