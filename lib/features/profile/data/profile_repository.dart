import 'models/profile_edit.dart';
import 'models/user_profile.dart';

/// Contract for the profile feature. Implementations decide where identity and
/// sections come from (mock now; an API impl reading /session + resume-service
/// later). UI/notifiers depend only on this interface.
abstract interface class ProfileRepository {
  Future<UserProfile> getMyProfile();
  Future<UserProfile> updateProfile(ProfileEdit edit);

  /// Read-only profile of another user by their public handle (custom userId,
  /// e.g. `nitin-1`) — powers opening a feed author's profile.
  Future<UserProfile> getPublicProfile(String handle);
}
