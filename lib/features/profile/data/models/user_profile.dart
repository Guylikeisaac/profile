import 'profile_links.dart';

/// One skill on the user's resume, **with its server id**.
///
/// The id matters: per-experience "hands-on" skills are written as
/// `usedSkills: [<uuid>]` but read back as full objects, so the app has to
/// keep the ids it was given — a name is not enough to link a skill to a role.
/// [UserProfile.categorizedSkills] stays name-only for the display cards;
/// [UserProfile.skillCatalog] is the id-carrying source the picker uses.
class ProfileSkill {
  final String id;
  final String name;

  /// Category header the skill sits under, uppercased to match
  /// [UserProfile.categorizedSkills] keys. Empty when the server didn't say.
  final String category;

  const ProfileSkill({
    required this.id,
    required this.name,
    this.category = '',
  });

  @override
  bool operator ==(Object other) =>
      other is ProfileSkill && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A single experience or education row, normalized for display.
///
/// The display fields (title/subtitle/meta/bullets/trailingBadge) drive the
/// read-only cards. The optional "raw" fields below are populated only for
/// backend-sourced Experience/Education records so the edit sheets can
/// round-trip them (update/delete by [id], real `DateTime` instead of parsing
/// the formatted [meta], the persisted accent color, and the enum/grade
/// values). They stay null for mock/display-only entries.
class ProfileEntry {
  final String title;
  final String subtitle;
  final String? meta;
  final List<String> bullets;
  final String? trailingBadge;

  // ── Raw backend fields (Experience/Education edit round-trip) ──────────────
  /// Server record id — required to PUT/DELETE this row. Null = not persisted.
  final String? id;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool currentlyWorking;

  /// Persisted accent hex (e.g. `#6366F1`), when the entity supports it.
  final String? accentColorHex;

  /// Resume-service location id + a display label, when the record has one.
  final String? locationId;
  final String? locationLabel;

  // Experience-only.
  final String?
      workMode; // fulltime · parttime · contract · internship · freelance · self_employed
  final String? locationType; // onsite · remote · hybrid · other
  final String? description;

  /// Company website stored on the record.
  ///
  /// The app has no field for this — it's a website-only input — but it is
  /// carried here so an edit can send it back unchanged. `PUT /experience`
  /// validates this key with a Zod chain whose `.transform()` runs even when
  /// the key is absent, turning "not sent" into an explicit `null`; echoing
  /// the stored value is what stops a mobile edit from wiping a website the
  /// user set on the web.
  final String? companyWebsite;

  /// Skills the user marked as used in this role, as the server returned them
  /// (objects with ids). Empty for education rows and for records with none.
  final List<ProfileSkill> usedSkills;

  // Education-only.
  final String? degreeName;
  final String? fieldOfStudyName;
  final String? grade;

  const ProfileEntry({
    required this.title,
    required this.subtitle,
    this.meta,
    this.bullets = const [],
    this.trailingBadge,
    this.id,
    this.startDate,
    this.endDate,
    this.currentlyWorking = false,
    this.accentColorHex,
    this.locationId,
    this.locationLabel,
    this.workMode,
    this.locationType,
    this.description,
    this.companyWebsite,
    this.usedSkills = const [],
    this.degreeName,
    this.fieldOfStudyName,
    this.grade,
  });
}

class TechnicalSkill {
  final String name;
  final String level;
  final String experience;
  final double progress;
  final int colorValue;

  const TechnicalSkill({
    required this.name,
    required this.level,
    required this.experience,
    required this.progress,
    required this.colorValue,
  });
}

class LanguageEntry {
  final String name;
  final String level;
  final double progress;

  const LanguageEntry({
    required this.name,
    required this.level,
    required this.progress,
  });
}

class ProjectEntry {
  final String title;
  final String subtitle;

  // ── Raw backend fields (Projects edit round-trip) ──────────────────────────
  /// Server record id — required to PUT/DELETE this project. Null = not saved.
  final String? id;
  final String? description;
  final String? linkUrl;

  /// Extra links beyond [linkUrl] (server cap: 5). Round-tripped on edit so a
  /// mobile save can't silently drop links added on the website.
  final List<String> additionalLinks;

  /// Resolved (public) cover image URL for the tile, if the project has one.
  final String? coverUrl;

  /// The S3 key(s) already attached to the project — sent back unchanged on an
  /// edit that doesn't replace the cover, so the cover isn't dropped.
  final List<String> attachmentKeys;

  final bool currentlyWorking;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? experienceId;
  final int? sortOrder;

  /// Technologies the project is built with ("React", "Docker"…), shown as
  /// icon tiles on the card. Not yet part of the backend payload.
  final List<String> techStack;

  /// A write-up of the project, opened from the card's "Case study" button.
  /// Not yet part of the backend payload.
  final String? caseStudyUrl;

  const ProjectEntry({
    required this.title,
    required this.subtitle,
    this.id,
    this.description,
    this.linkUrl,
    this.additionalLinks = const [],
    this.coverUrl,
    this.attachmentKeys = const [],
    this.currentlyWorking = false,
    this.startDate,
    this.endDate,
    this.experienceId,
    this.sortOrder,
    this.techStack = const [],
    this.caseStudyUrl,
  });
}

/// Aggregate of everything the profile screen renders. Loaded by
/// [ProfileRepository] — the screen never receives this via constructor args.
class UserProfile {
  final String id;
  final String userId;
  final String name;
  final String title;
  final String profilePic;
  final String? banner;
  final String? location;
  final String company;
  final String department;
  final String industry;
  final String handle;
  final String website;
  final String about;
  final bool openToWork;
  final int? completionPercent;

  /// Profile-view count (auth-service `impressionCount`). Present for the
  /// signed-in user via the session; 0 for others.
  final int impressionCount;
  final List<ProfileEntry> experiences;
  final List<ProfileEntry> educations;
  final List<String> skills;
  final Map<String, List<String>> categorizedSkills;

  /// The same skills as [categorizedSkills], flat and **with their ids**.
  ///
  /// Kept alongside rather than replacing the name-keyed map: the display
  /// cards and the skills editor only ever need names, while the per-role
  /// picker needs ids to write `usedSkills`.
  final List<ProfileSkill> skillCatalog;
  final List<TechnicalSkill> technicalSkills;
  final List<LanguageEntry> languages;
  final List<ProjectEntry> projects;

  /// Typed social/portfolio links (LinkedIn, GitHub, …) from work-details.
  final ProfileLinks links;

  /// Saved solid cover colour (`profileBannerColor`, e.g. `#0EA5E9`), when set.
  final String? bannerColor;

  /// Saved per-category skill accent colours (`skillCategoryAccentColors`),
  /// keyed by category name (uppercased to match [categorizedSkills]).
  final Map<String, String> skillCategoryColors;

  /// Intro audio/video state, when the user has one.
  final String? introMediaUrl;
  final String? introMediaType; // 'audio' | 'video'
  final bool introMediaPublic;

  const UserProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.title,
    required this.profilePic,
    this.banner,
    this.location,
    this.company = '',
    this.department = '',
    this.industry = '',
    this.handle = '',
    this.website = '',
    this.about = '',
    this.openToWork = false,
    this.completionPercent,
    this.impressionCount = 0,
    this.experiences = const [],
    this.educations = const [],
    this.skills = const [],
    this.categorizedSkills = const {},
    this.skillCatalog = const [],
    this.technicalSkills = const [],
    this.languages = const [],
    this.projects = const [],
    this.links = ProfileLinks.empty,
    this.bannerColor,
    this.skillCategoryColors = const {},
    this.introMediaUrl,
    this.introMediaType,
    this.introMediaPublic = false,
  });
}
