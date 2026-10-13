import '../../../core/data/repository_exception.dart';
import 'models/profile_edit.dart';
import 'models/user_profile.dart';
import 'profile_repository.dart';

/// In-memory mock. Realistic latency + an opt-in failure switch so the UI can
/// be built and its loading/error states exercised without the backend.
class MockProfileRepository implements ProfileRepository {
  MockProfileRepository();

  /// Flip in tests/dev to exercise the error path.
  bool failNext = false;

  UserProfile _profile = _sample;

  @override
  Future<UserProfile> getMyProfile() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (failNext) {
      throw const RepositoryException('Could not load your profile.');
    }
    return _profile;
  }

  @override
  Future<UserProfile> getPublicProfile(String handle) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (failNext) {
      throw const RepositoryException('Could not load this profile.');
    }
    return _profile;
  }

  @override
  Future<UserProfile> updateProfile(ProfileEdit edit) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (failNext) {
      throw const RepositoryException('Could not save your profile.');
    }
    _profile = UserProfile(
      id: _profile.id,
      userId: _profile.userId,
      name: edit.name,
      title: edit.headline,
      profilePic: _profile.profilePic,
      banner: _profile.banner,
      location: edit.location,
      company: edit.company,
      department: _profile.department,
      industry: _profile.industry,
      handle: edit.handle,
      website: edit.website,
      about: edit.about,
      openToWork: edit.openToWork,
      completionPercent: _profile.completionPercent,
      experiences: _profile.experiences,
      educations: _profile.educations,
      skills: _profile.skills,
      categorizedSkills: _profile.categorizedSkills,
      technicalSkills: _profile.technicalSkills,
      languages: _profile.languages,
      projects: _profile.projects,
    );
    return _profile;
  }

  static const UserProfile _sample = UserProfile(
    id: 'mock-1',
    userId: 'alexjohnson',
    name: 'Alex Johnson',
    title: 'Product Designer',
    profilePic: '',
    banner: '',
    location: 'Bangalore, India',
    company: 'Syncvtiv',
    department: 'Design',
    industry: 'Software',
    handle: '@alexjohnson234',
    website: 'alexjohnson.design',
    about: 'Tell people about yourself...',
    openToWork: true,
    completionPercent: 60,
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
    skills: ['Figma', 'Prototyping', 'Design Systems', 'User Research'],
    categorizedSkills: {
      'DESIGN': ['Figma', 'Adobe XD', 'Sketch', 'Prototyping', 'Wireframing'],
      'RESEARCH': [
        'User Testing',
        'Heuristic Eval.',
        'A/B Testing',
        'Analytics'
      ],
      'SOFT SKILLS': [
        'Leadership',
        'Stakeholder Mgmt',
        'Presentation',
        'Agile'
      ],
    },
    technicalSkills: [
      TechnicalSkill(
        name: 'Figma',
        level: 'Expert',
        experience: '4y 2m',
        progress: 0.88,
        colorValue: 0xFF7A6BFF,
      ),
      TechnicalSkill(
        name: 'Adobe XD',
        level: 'Expert',
        experience: '3y',
        progress: 0.82,
        colorValue: 0xFF7A6BFF,
      ),
      TechnicalSkill(
        name: 'Prototyping',
        level: 'Advanced',
        experience: '3y',
        progress: 0.68,
        colorValue: 0xFF7A6BFF,
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
        progress: 0.55,
        colorValue: 0xFF48D4BF,
      ),
    ],
    languages: [
      LanguageEntry(name: 'English', level: 'Native', progress: 0.98),
      LanguageEntry(name: 'Hindi', level: 'Fluent', progress: 0.92),
      LanguageEntry(name: 'Marathi', level: 'Conversational', progress: 0.60),
    ],
    projects: [
      ProjectEntry(title: 'SyncUp App', subtitle: 'Mobile App'),
      ProjectEntry(title: 'Fintech Dashboard', subtitle: 'Web App'),
      ProjectEntry(title: 'Design System', subtitle: 'Design System'),
      ProjectEntry(title: 'UX Research', subtitle: 'Research'),
    ],
  );
}
