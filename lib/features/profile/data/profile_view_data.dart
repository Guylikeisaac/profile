import 'package:flutter/material.dart';

import '../../../core/helpers/work_link_url.dart';
import '../../../core/helpers/avatar_url.dart';
import 'models/profile_links.dart';
import 'models/user_profile.dart';

/// The three faithful renderings of one profile, per the design spec:
/// owner/edit surface, visitor/contact surface, and shareable CV export.
enum ProfileViewMode { selfView, publicView, cv }

extension ProfileViewModeX on ProfileViewMode {
  bool get isSelf => this == ProfileViewMode.selfView;
  bool get isCv => this == ProfileViewMode.cv;

  /// Activity feed shows on Self + Public, never on the CV export.
  bool get showsActivity => this != ProfileViewMode.cv;
}

/// A single hero-stat column — bold value over a gray caption.
class ProfileStat {
  final String value;
  final String caption;

  const ProfileStat(this.value, this.caption);
}

/// Brand identity for the tinted social-link / contact chips.
enum ProfileBrand { syncup, github, dribbble, whatsapp, portfolio, email }

/// Visual style (tint + label) for a [ProfileBrand] chip. The leading glyph is
/// chosen per-brand in the chip widget (FontAwesome brand marks render via
/// `FaIcon`, so the glyph can't be stored here as a plain `IconData`).
class ProfileBrandStyle {
  final String label;
  final Color fill;
  final Color foreground;

  const ProfileBrandStyle({
    required this.label,
    required this.fill,
    required this.foreground,
  });
}

/// Tints sampled from the spec (soft brand-tint fill + matching label color).
///
/// These are **brand identity values** and stay fixed in both themes — a
/// GitHub chip is GitHub-coloured wherever it appears. What must not stay fixed
/// is how they are *rendered*: several foregrounds are near-black (GitHub
/// `#24292E`) and several fills are near-white, so on a dark page the chip
/// would be an unreadable pale block.
///
/// [profileBrandStyleFor] resolves that at render time — see there. Nothing
/// should read this map directly.
///
/// This is why `profile_view_data.dart` stays on
/// `tool/raw_colors_allowlist.txt`.
const Map<ProfileBrand, ProfileBrandStyle> kProfileBrandStyles = {
  ProfileBrand.syncup: ProfileBrandStyle(
    label: 'SyncUp',
    fill: Color(0xFFEEF0FE),
    foreground: Color(0xFF5B5FF5),
  ),
  ProfileBrand.github: ProfileBrandStyle(
    label: 'GitHub',
    fill: Color(0xFFF1F1F4),
    foreground: Color(0xFF24292E),
  ),
  ProfileBrand.dribbble: ProfileBrandStyle(
    label: 'Dribbble',
    fill: Color(0xFFFCE7F3),
    foreground: Color(0xFFEC4899),
  ),
  ProfileBrand.whatsapp: ProfileBrandStyle(
    label: 'WhatsApp',
    fill: Color(0xFFE7F8EF),
    foreground: Color(0xFF1FA855),
  ),
  ProfileBrand.portfolio: ProfileBrandStyle(
    label: 'Portfolio',
    fill: Color(0xFFEEF0FE),
    foreground: Color(0xFF5B5FF5),
  ),
  ProfileBrand.email: ProfileBrandStyle(
    label: 'Email',
    fill: Color(0xFFEEF0FE),
    foreground: Color(0xFF5B5FF5),
  ),
};

/// Everything the three profile views render. Spec-derived static mock — kept
/// self-contained so these UI screens don't depend on the async mock
/// repository or its loading/error states.
class ProfileViewData {
  final String name;
  final String role;
  final String company;
  final String department;
  final String industry;
  final String location;
  final bool openToWork;
  final String bio;

  /// Resolved profile picture / banner URLs (empty when unset → initials
  /// fallback for avatar surfaces).
  final String avatarUrl;
  final String bannerUrl;

  /// Saved solid cover colour hex (`#RRGGBB`) — tints the hero when set.
  final String? bannerColor;

  /// Saved per-category skill accent colours (category → hex), keyed uppercase.
  final Map<String, String> skillCategoryColors;

  /// 3-column "social vanity" stats (Self + Public).
  final List<ProfileStat> socialStats;

  /// 4-column resume metrics (CV).
  final List<ProfileStat> resumeStats;

  /// Portfolio/social links as detected platforms, real from the backend (Self
  /// card + Public quick-contact pills both render these). Multi-link columns
  /// are already expanded — see [ProfileLinks.resolved].
  final List<WorkLink> socialLinks;

  final List<ProfileEntry> experiences;
  final List<ProfileEntry> educations;
  final Map<String, List<String>> categorizedSkills;
  final List<TechnicalSkill> technicalSkills;
  final List<LanguageEntry> languages;
  final List<ProjectEntry> projects;

  const ProfileViewData({
    required this.name,
    required this.role,
    required this.company,
    required this.department,
    required this.industry,
    required this.location,
    required this.openToWork,
    required this.bio,
    this.avatarUrl = '',
    this.bannerUrl = '',
    this.bannerColor,
    this.skillCategoryColors = const {},
    required this.socialStats,
    required this.resumeStats,
    required this.socialLinks,
    required this.experiences,
    required this.educations,
    required this.categorizedSkills,
    required this.technicalSkills,
    required this.languages,
    required this.projects,
  });

  /// Adapts a backend [UserProfile] into the view model the three profile
  /// screens render. Identity fields (name, role, company, location, bio) are
  /// real-only: a missing value stays empty and the views render an honest
  /// empty state (hidden line / "No bio added yet") — never Alex Johnson
  /// placeholder content. The Activity section is fully live now (see
  /// `ActivitySection` + `activityFeedProvider`); the only remaining
  /// [kMockProfileViewData] fallbacks are the stats decorations, which the
  /// screens override with real values before rendering.
  factory ProfileViewData.fromUserProfile(UserProfile u) {
    const placeholder = kMockProfileViewData;
    return ProfileViewData(
      name: u.name,
      role: u.title,
      company: u.company,
      department: u.department,
      industry: u.industry,
      location: u.location ?? '',
      openToWork: u.openToWork,
      bio: u.about,
      avatarUrl: sanitizeAvatarUrl(u.profilePic),
      bannerUrl: u.banner ?? '',
      bannerColor: u.bannerColor,
      skillCategoryColors: u.skillCategoryColors,
      // No clean backend source yet — keep placeholders.
      socialStats: placeholder.socialStats,
      resumeStats: placeholder.resumeStats,
      // Real from the resume work-details / projects payloads (empty stays
      // empty so the section shows its honest empty state, not placeholder data).
      socialLinks: u.links.resolved,
      projects: u.projects,
      experiences: u.experiences,
      educations: u.educations,
      categorizedSkills: u.categorizedSkills,
      languages: u.languages,
      // No backend source for technical-skill proficiency bars — never shown.
      technicalSkills: const [],
    );
  }
}

/// The single Alex Johnson profile, content lifted directly from the spec's
/// "Extract All Visible Mock Data" section.
const ProfileViewData kMockProfileViewData = ProfileViewData(
  name: 'Alex Johnson',
  role: 'UI UX Designer',
  company: 'Synctiv',
  department: 'Design',
  industry: 'Software',
  location: 'Bhopal, India',
  openToWork: true,
  bio: 'Passionate Product Designer specializing in UI and UX Design, creating '
      'seamless & intuitive digital experiences. Skilled in user research. '
      'prototyping.',
  socialStats: [
    ProfileStat('4+', 'Yrs Exp'),
    ProfileStat('500+', 'Connections'),
    ProfileStat('2.4k', 'Profile Views'),
  ],
  resumeStats: [
    ProfileStat('4+', 'Years Exp'),
    ProfileStat('38+', 'Projects'),
    ProfileStat('12', 'Skills'),
    ProfileStat('500+', 'Network'),
  ],
  // Social links are real from the backend now; the placeholder set is empty.
  socialLinks: [],
  experiences: [
    ProfileEntry(
      title: 'Senior UI/UX Designer',
      subtitle: 'Synctiv',
      meta: 'Feb 2025 – Present',
      trailingBadge: 'Now',
      bullets: [
        'Led design for 3 product launches from 0 → 1',
        'Built company-wide design system for 8 teams',
        'Improved user drop-off by 34% through UX audit',
      ],
    ),
    ProfileEntry(
      title: 'Product Designer',
      subtitle: 'Product Inc.',
      meta: 'Feb 2024 – Jan 2025',
      trailingBadge: '1 yr',
      bullets: [
        'Redesigned checkout flow → 28% conversion lift',
        'Mentored 2 junior designers',
      ],
    ),
    ProfileEntry(
      title: 'UI Designer',
      subtitle: 'TCS',
      meta: 'Mar 2021 – Dec 2021',
      trailingBadge: '10 mo',
      bullets: [
        'Delivered dashboards for 5 enterprise clients',
      ],
    ),
  ],
  educations: [
    ProfileEntry(
      title: 'Arena Multimedia',
      subtitle: 'Adv. Diploma - Multimedia Design',
      meta: '2014 – 2017',
      trailingBadge: 'Distinction',
    ),
    ProfileEntry(
      title: 'Oxford University',
      subtitle: 'BSc Psychology',
      meta: '2012 – 2013',
      trailingBadge: 'First Class',
    ),
  ],
  categorizedSkills: {
    'DESIGN': ['Figma', 'Adobe XD', 'Sketch', 'Prototyping', 'Wireframing'],
    'RESEARCH': ['User Testing', 'Heuristic Eval.', 'A/B Testing', 'Analytics'],
    'SOFT SKILLS': ['Leadership', 'Stakeholder Mgmt', 'Presentation', 'Agile'],
  },
  technicalSkills: [
    TechnicalSkill(
      name: 'Figma',
      level: 'Expert',
      experience: '4y 2m',
      progress: 0.88,
      colorValue: 0xFF6366F1,
    ),
    TechnicalSkill(
      name: 'Adobe XD',
      level: 'Expert',
      experience: '3y',
      progress: 0.82,
      colorValue: 0xFF6366F1,
    ),
    TechnicalSkill(
      name: 'Prototyping',
      level: 'Advanced',
      experience: '3y',
      progress: 0.68,
      colorValue: 0xFF6366F1,
    ),
    TechnicalSkill(
      name: 'User Testing',
      level: 'Intermediate',
      experience: '2y',
      progress: 0.55,
      colorValue: 0xFF48D4BF,
    ),
    TechnicalSkill(
      name: 'Motion Design',
      level: 'Intermediate',
      experience: '1y 6m',
      progress: 0.50,
      colorValue: 0xFF48D4BF,
    ),
  ],
  languages: [
    LanguageEntry(name: 'English', level: 'Native', progress: 0.98),
    LanguageEntry(name: 'Hindi', level: 'Fluent', progress: 0.85),
    LanguageEntry(name: 'Marathi', level: 'Conversational', progress: 0.55),
  ],
  projects: [
    ProjectEntry(title: 'SyncUp App', subtitle: 'Mobile App'),
    ProjectEntry(title: 'Fintech Dashboard', subtitle: 'Web App'),
    ProjectEntry(title: 'Design System', subtitle: 'Design System'),
    ProjectEntry(title: 'UX Research', subtitle: 'Research'),
  ],
);

/// The chip style for [brand], adjusted for the active surface.
///
/// The brand's **hue survives**; only lightness moves, and only when the stock
/// value would be illegible:
///
///  * the fill is composited toward the page so a near-white brand tint does
///    not become a bright block on a dark page;
///  * the foreground goes through [readableBrandColor], which lifts near-black
///    marks until they clear the 3:1 non-text minimum.
ProfileBrandStyle profileBrandStyleFor(
  BuildContext context,
  ProfileBrand brand,
) {
  final base = kProfileBrandStyles[brand]!;
  final surface = Theme.of(context).colorScheme.surfaceContainerHigh;

  // Both adjustments live in `work_link_url.dart` alongside the app's other
  // brand-colour logic, so this stays a lookup rather than a branch.
  return ProfileBrandStyle(
    label: base.label,
    fill: readableBrandFill(base.fill, base.foreground, surface),
    foreground: readableBrandColor(base.foreground, surface),
  );
}
