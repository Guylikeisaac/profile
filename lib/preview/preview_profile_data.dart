import '../features/post/data/models/post_models.dart';
import '../features/profile/data/models/certification.dart';
import '../features/profile/data/models/profile_links.dart';
import '../features/profile/data/models/profile_reference.dart';
import '../features/profile/data/models/user_profile.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/resume/data/models/resume_file.dart';

/// Sample people, photos and content for the profile design preview
/// (`lib/main_profile_preview.dart`). Photos are Unsplash images, which are
/// served with CORS headers so the web build can draw them.
abstract final class PreviewData {
  static String _photo(String id, {int w = 400}) =>
      'https://images.unsplash.com/photo-$id?w=$w&q=80&auto=format&fit=crop';

  static final String avatar = _photo('1507003211169-0a1dd7228f2d', w: 320);
  static final String banner = _photo('1451187580459-43490279c0fa', w: 1400);

  static final UserProfile profile = UserProfile(
    id: 'preview-arjun',
    userId: 'arjun-mehta',
    name: 'Arjun Mehta',
    title: 'Senior Product Designer',
    profilePic: avatar,
    banner: banner,
    location: 'Bengaluru, India',
    company: 'Razorpay',
    department: 'Design',
    industry: 'Fintech',
    handle: '@arjun-mehta',
    website: 'arjunmehta.design',
    about: 'Product designer who turns messy money problems into calm, '
        'obvious interfaces. 7 years shipping payments, onboarding and '
        'design systems used by millions. I care about motion, type and '
        'the 2% of details nobody asks for but everybody feels.',
    openToWork: true,
    impressionCount: 1284,
    links: const ProfileLinks(
      linkedinUrl: 'https://www.linkedin.com/in/arjun-mehta',
      githubUrl: 'https://github.com/arjunmehta',
      behanceUrl: 'https://www.behance.net/arjunmehta',
      twitterUrl: 'https://x.com/arjunmehta',
      personalWebsite: 'https://arjunmehta.design',
    ),
    experiences: [
      ProfileEntry(
        title: 'Senior Product Designer',
        subtitle: 'Razorpay',
        companyWebsite: 'https://razorpay.com',
        meta: 'Mar 2023 – Present',
        trailingBadge: 'Now',
        startDate: DateTime(2023, 3),
        currentlyWorking: true,
        bullets: const [
          'Led the redesign of Checkout used by 8M+ merchants',
          'Cut payment drop-off by 18% with a one-tap UPI flow',
          'Built the "Blade" design system adopted by 14 teams',
        ],
      ),
      ProfileEntry(
        title: 'Product Designer',
        subtitle: 'Swiggy',
        companyWebsite: 'https://swiggy.com',
        meta: 'Jun 2020 – Feb 2023',
        trailingBadge: '2 yr 9 mo',
        startDate: DateTime(2020, 6),
        endDate: DateTime(2023, 2),
        bullets: const [
          'Designed Instamart onboarding from zero to launch',
          'Shipped live order tracking with real-time map motion',
        ],
      ),
      ProfileEntry(
        title: 'UI/UX Designer',
        subtitle: 'Zomato',
        companyWebsite: 'https://zomato.com',
        meta: 'Jul 2018 – May 2020',
        trailingBadge: '1 yr 11 mo',
        startDate: DateTime(2018, 7),
        endDate: DateTime(2020, 5),
        bullets: const [
          'Owned restaurant discovery and search experiences',
        ],
      ),
    ],
    educations: const [
      ProfileEntry(
        title: 'National Institute of Design',
        subtitle: 'M.Des · Interaction Design',
        meta: '2016 – 2018',
        trailingBadge: '9.1 CGPA',
      ),
      ProfileEntry(
        title: 'IIT Bombay',
        subtitle: 'B.Des · Industrial Design',
        meta: '2012 – 2016',
        trailingBadge: 'First Class',
      ),
    ],
    skills: const ['Figma', 'Prototyping', 'Design Systems', 'User Research'],
    categorizedSkills: const {
      'DESIGN': [
        'Figma',
        'Framer',
        'Prototyping',
        'Interaction Design',
        'Motion',
        'Design Systems',
      ],
      'RESEARCH': ['Usability Testing', 'Interviews', 'A/B Testing', 'Analytics'],
      'BUILD': ['HTML/CSS', 'React', 'Flutter', 'Lottie'],
      'LEADERSHIP': ['Mentoring', 'Workshops', 'Stakeholder Mgmt'],
    },
    languages: const [
      LanguageEntry(name: 'English', level: 'Fluent', progress: 0.95),
      LanguageEntry(name: 'Hindi', level: 'Native', progress: 1),
      LanguageEntry(name: 'Gujarati', level: 'Conversational', progress: 0.6),
    ],
    projects: [
      ProjectEntry(
        title: 'Razorpay Checkout 2.0',
        subtitle: 'Payments · Mobile & Web',
        description: 'A faster, calmer checkout for 8M merchants.',
        linkUrl: 'https://razorpay.com/checkout',
        coverUrl: _photo('1460925895917-afdab827c52f', w: 800),
      ),
      ProjectEntry(
        title: 'Blade Design System',
        subtitle: 'Design System',
        description: '300+ components, tokens and motion guidelines.',
        linkUrl: 'https://blade.razorpay.com',
        coverUrl: _photo('1551288049-bebda4e38f71', w: 800),
      ),
      ProjectEntry(
        title: 'Instamart Onboarding',
        subtitle: 'Mobile App',
        description: 'From first open to first order in 40 seconds.',
        coverUrl: _photo('1498050108023-c5249f4df085', w: 800),
      ),
    ],
  );

  static final List<Certification> certifications = [
    Certification(
      id: 'c1',
      name: 'Google UX Design Professional Certificate',
      issuingOrganization: 'Google',
      issueDate: DateTime(2022, 8),
      credentialId: 'GUX-88213',
      status: CertificationStatus.verified,
      verifiedAt: DateTime(2022, 9),
    ),
    Certification(
      id: 'c2',
      name: 'Certified Usability Analyst',
      issuingOrganization: 'Human Factors International',
      issueDate: DateTime(2021, 3),
      status: CertificationStatus.verified,
      verifiedAt: DateTime(2021, 4),
    ),
    Certification(
      id: 'c3',
      name: 'Interaction Design Specialization',
      issuingOrganization: 'UC San Diego · Coursera',
      issueDate: DateTime(2019, 11),
      status: CertificationStatus.pending,
    ),
  ];

  static final List<ProfileReference> references = [
    ProfileReference(
      id: 'r1',
      reviewerName: 'Priya Sharma',
      reviewer: ReferenceUser(
        id: 'u-priya',
        handle: 'priya-sharma',
        name: 'Priya Sharma',
        title: 'Head of Design, Razorpay',
        profilePic: _photo('1494790108377-be9c29b29330', w: 200),
      ),
      reviewerTitle: 'Head of Design',
      reviewerCompany: 'Razorpay',
      relationship: 'Manager',
      reviewText: 'Arjun has the rare mix of craft and judgement — he knows '
          'which details matter and sweats every one of them.',
      status: ReferenceStatus.approved,
      approvedAt: DateTime(2025, 6, 2),
    ),
    ProfileReference(
      id: 'r2',
      reviewerName: 'Rahul Verma',
      reviewer: ReferenceUser(
        id: 'u-rahul',
        handle: 'rahul-verma',
        name: 'Rahul Verma',
        title: 'Engineering Manager, Swiggy',
        profilePic: _photo('1500648767791-00dcc994a43e', w: 200),
      ),
      reviewerTitle: 'Engineering Manager',
      reviewerCompany: 'Swiggy',
      relationship: 'Colleague',
      reviewText: 'The best designer-engineer partnership I have had. His '
          'specs are so clear they read like code.',
      status: ReferenceStatus.approved,
      approvedAt: DateTime(2024, 11, 18),
    ),
  ];

  static final ResumeFile resume = ResumeFile(
    id: 'resume-1',
    resumeKey: 'Arjun_Mehta_Product_Designer_2026.pdf',
    uploadedAt: DateTime(2026, 9, 21),
  );

  static Map<String, dynamic> _author() => {
        'id': profile.id,
        'userId': profile.userId,
        'name': profile.name,
        'profilePic': avatar,
        'userTitle': profile.title,
      };

  static Map<String, dynamic> _post(
    String id,
    String content,
    List<String> photos,
    Map<String, int> reactions,
    int comments,
    int daysAgo,
  ) =>
      {
        'id': id,
        'content': content,
        'author': _author(),
        'media': [
          for (var i = 0; i < photos.length; i++)
            {
              'id': '$id-m$i',
              'type': 'IMAGE',
              'url': _photo(photos[i], w: 1000),
              'mimeType': 'image/jpeg',
              'fileName': '$id-$i.jpg',
            },
        ],
        'interactionCounts': reactions,
        'commentCount': comments,
        'createdAt': DateTime.now()
            .subtract(Duration(days: daysAgo, hours: 3))
            .toUtc()
            .toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'visibility': 'PUBLIC',
      };

  static PostResponse posts() => PostResponse.fromJson({
        'hasMore': false,
        'posts': [
          _post(
            'p1',
            'Shipped Checkout 2.0 today 🚀 Eighteen months, 40+ usability '
                'sessions and one very patient engineering team. The biggest '
                'lesson: remove a step before you polish it.',
            ['1460925895917-afdab827c52f'],
            {'LIKE': 214, 'LOVE': 48, 'WOW': 12},
            37,
            2,
          ),
          _post(
            'p2',
            'Our design team offsite in Goa — two days of sketching, '
                'arguing about border radii and eating far too much.',
            ['1522071820081-009f0129c71c', '1519389950473-47ba0277781c'],
            {'LIKE': 162, 'SMILE': 29},
            21,
            9,
          ),
          _post(
            'p3',
            'Hot take: a design system is a product, not a Figma file. '
                'It needs a roadmap, users and a support channel.',
            const [],
            {'LIKE': 98, 'WOW': 7},
            14,
            16,
          ),
          _post(
            'p4',
            'Weekend side project: a tiny Flutter app for tracking chai '
                'intake ☕ Motion prototypes in the comments.',
            ['1555066931-4365d14bab8c'],
            {'LIKE': 76, 'LOVE': 19},
            9,
            30,
          ),
        ],
      });
}

/// The preview's profile source: always [PreviewData.profile].
class PreviewProfileRepository implements ProfileRepository {
  @override
  Future<UserProfile> getMyProfile() async => PreviewData.profile;

  @override
  Future<UserProfile> getPublicProfile(String handle) async =>
      PreviewData.profile;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(UnsupportedError('preview'));
}
