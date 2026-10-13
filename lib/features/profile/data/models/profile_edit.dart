/// Input model for editing the current user's profile.
class ProfileEdit {
  final String name;
  final String headline;
  final String company;
  final String location;

  /// Set only when the user picked a new location from the picker — drives the
  /// `current-location` write. Null means "location unchanged".
  final String? locationId;
  final String handle;
  final String website;
  final String about;
  final bool openToWork;

  const ProfileEdit({
    required this.name,
    required this.headline,
    required this.company,
    required this.location,
    this.locationId,
    required this.handle,
    required this.website,
    required this.about,
    required this.openToWork,
  });
}
