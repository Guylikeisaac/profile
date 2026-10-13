import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_manager.dart';
import '../../../core/providers/api_client_provider.dart';
import '../../../core/state/submit_status.dart';
import '../../home/providers/feed_provider.dart';
import '../../network/data/connection_repository.dart';
import '../../network/providers/network_providers.dart';
import '../../profile_menu/providers/profile_menu_provider.dart';
import '../../readiness_sprint/providers/sprint_providers.dart';
import '../data/api_profile_repository.dart';
import '../data/models/profile_edit.dart';
import '../data/models/user_profile.dart';
import '../data/profile_media_repository.dart';
import '../data/profile_repository.dart';
import '../data/projects_repository.dart';
import '../data/resume_sections_repository.dart';

/// Real read repo: aggregates `/auth/session` + `/resume/work-details` into a
/// [UserProfile] (the onboarding "carry-forward"). Writes are still a stub —
/// see [ApiProfileRepository.updateProfile]. To go back to mock data, swap this
/// body to `MockProfileRepository()` or override the provider in a
/// `ProviderScope`.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ApiProfileRepository(ref.watch(apiClientProvider)),
);

/// Self-loading current-user profile. Errors propagate as `AsyncError`.
final myProfileProvider = FutureProvider.autoDispose<UserProfile>(
  (ref) => ref.watch(profileRepositoryProvider).getMyProfile(),
);

/// Read-only profile of another user by public handle (custom userId). Powers
/// opening a feed author's profile. Family-keyed so each handle caches
/// independently; auto-disposes when the public profile screen leaves.
final publicProfileProvider =
    FutureProvider.autoDispose.family<UserProfile, String>(
  (ref, handle) =>
      ref.watch(profileRepositoryProvider).getPublicProfile(handle),
);

/// Everything the *other-user* public profile needs on first paint, fetched
/// together so the hero renders the correct Connect state + Connections stat
/// immediately (no "Connect" flash before the real relationship is known).
/// The profile read is fatal; the connection calls degrade (unknown → Connect
/// / hidden stat) so a connection-service hiccup never blocks the profile.
class PublicProfileBundle {
  final UserProfile profile;
  final PublicConnectState connect;

  const PublicProfileBundle(this.profile, this.connect);
}

/// `retry` is disabled deliberately, matching [postDetailProvider] and
/// [notificationsFeedProvider].
///
/// Riverpod 3 retries a failed provider with exponential backoff by default. On
/// the profile screen that turned a single upstream failure into a silent storm
/// against a 500ing endpoint — captured in a debug session as six
/// `GET /user/public/{handle}` calls in seven seconds, all 500, while the user
/// sat looking at a "Failed to get user profile" screen with a Retry button.
/// The screen already offers Retry and pull-to-refresh, so a failure that stays
/// failed is both honest and cheaper.
final publicProfileBundleProvider = FutureProvider.autoDispose
    .family<PublicProfileBundle, String>(retry: (_, __) => null,
        (ref, handle) async {
  final profileRepo = ref.watch(profileRepositoryProvider);
  final connRepo = ref.watch(connectionRepositoryProvider);

  // The profile is fetched FIRST, on purpose, even though a parallel fetch
  // would be one round trip faster.
  //
  // Connection rows key on the **auth UUID** (`sentFrom`/`sentTo`), and the
  // only place this screen can learn the peer's UUID is the profile response's
  // `user.id` — the route argument is the public handle. Running the two calls
  // in parallel therefore forced the status lookup to use the handle, and that
  // is exactly the bug this ordering fixes: on staging,
  // `GET /connection/status/monika-jiwnani` answered
  // `{"isConnected": false}` for a pair that `GET /connection/accepted`
  // reported as ACCEPTED in the same second. The profile said "Connect" about
  // someone already in My Network and already in the chat inbox.
  //
  // The service is *supposed* to resolve a handle
  // (`handleCheckConnectionStatus` matches `uniqueId` OR `userId`), but it
  // demonstrably did not, and every other correct caller in this app already
  // sends the UUID — bulk status, chat's `targetUserId`, and
  // `sendConnection`/`withdrawConnection`. Depending on the handle alias was
  // the mistake; the UUID is the identifier connections are actually stored
  // under.
  final profile = await profileRepo.getPublicProfile(handle);

  // Status stays non-fatal: a connection-service hiccup must not blank a
  // profile that loaded fine. It degrades to "no relationship", which shows
  // Connect — the same thing a genuinely unconnected profile shows.
  //
  // We do NOT fetch the other user's total connection count —
  // `connection/count` is unreliable (returns 0 for users with real
  // connections), so the hero omits that stat for other users rather than
  // showing a wrong number.
  var connect = const PublicConnectState(PublicConnectKind.none);
  if (profile.id.isNotEmpty) {
    try {
      connect = await connRepo.getConnectionState(profile.id);
    } catch (_) {
      // Left as "none" — see above.
    }
  }

  return PublicProfileBundle(profile, connect);
});

/// Write paths for the structured resume sections (Skills, Languages) behind
/// the profile edit sheets. Built from `apiClientProvider` so auth rides the
/// shared interceptor. After a save the sheet invalidates [myProfileProvider]
/// so the new data round-trips onto the profile.
///
/// Skills/experience edits also re-arm the Job Readiness Sprint (interim
/// device-local rule until the backend exposes eligibility) and refresh its
/// surfaces — wired here so the repo stays decoupled from the sprint feature.
final resumeSectionsRepositoryProvider = Provider<ResumeSectionsRepository>(
  (ref) => ResumeSectionsRepository(
    ref.watch(apiClientProvider),
    onHiringSignalChanged: () => notifySprintOfProfileUpdate(ref),
  ),
);

/// Projects create/update/delete + S3 cover upload behind the project sheet.
final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) => ProjectsRepository(ref.watch(apiClientProvider)),
);

/// Profile picture + banner presigned uploads (auth-service). Built from
/// `apiClientProvider` for the authed presign/attach calls; the S3 PUT itself
/// uses a clean Dio inside the repository.
final profileMediaRepositoryProvider = Provider<ProfileMediaRepository>(
  (ref) => ProfileMediaRepository(ref.watch(apiClientProvider)),
);

// ── Edit command ───────────────────────────────────────────────────────────

class ProfileEditState {
  final SubmitStatus status;
  final String? error;

  const ProfileEditState({this.status = SubmitStatus.idle, this.error});

  ProfileEditState copyWith({
    SubmitStatus? status,
    String? error,
    bool clearError = false,
  }) {
    return ProfileEditState(
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ProfileEditController extends Notifier<ProfileEditState> {
  @override
  ProfileEditState build() => const ProfileEditState();

  Future<bool> submit(ProfileEdit edit) async {
    state = state.copyWith(status: SubmitStatus.submitting, clearError: true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(edit);
      // Keep the signed-in app chrome in sync after scalar profile edits
      // (name/title/location/open-to-work/company/website/bio) instead of
      // waiting for the next app relaunch to refresh the session user.
      await AuthManager().refreshCurrentUser();
      // The write succeeded, so the submitted name/headline are authoritative
      // even if `/auth/session` briefly still returns the pre-edit user. Apply
      // them optimistically AFTER the session refresh so the welcome sheet /
      // header / drawer show the new values immediately (was: showed the old
      // value right after save, only correct on re-entry).
      AuthManager().applyLocalProfileEdits(
        name: edit.name,
        userTitle: edit.headline,
      );
      state = state.copyWith(status: SubmitStatus.success);
      ref.invalidate(myProfileProvider);
      ref.invalidate(profileSummaryProvider);
      ref.invalidate(homeFeedProvider);
      return true;
    } catch (e) {
      state = state.copyWith(status: SubmitStatus.error, error: e.toString());
      return false;
    }
  }
}

final profileEditControllerProvider =
    NotifierProvider<ProfileEditController, ProfileEditState>(
  ProfileEditController.new,
);
