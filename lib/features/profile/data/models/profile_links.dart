import '../../../../core/helpers/work_link_url.dart';

/// The link **columns** stored on the user's resume work-details, matching the
/// `PUT /resume/work-details/profile-links` contract exactly.
///
/// This is storage, not presentation: the user-facing platform model lives in
/// `core/helpers/work_link_url.dart` ([WorkLink] / [WorkLinkKind]), because the
/// backend has only nine dedicated columns for 22 detectable platforms and
/// stores the rest together in `personalWebsite`. Use [resolved] to go from
/// these columns to what the UI shows.
///
/// Every field is nullable: a null means "not set / clear this link" — the
/// write path sends only the fields the user actually changed (and sends an
/// explicit `null` to clear one), so an untouched link is never disturbed.
/// Typed profile links, read from / written to the resume work-details.
class ProfileLinks {
  final String? linkedinUrl;
  final String? githubUrl;
  final String? twitterUrl;
  final String? personalWebsite;
  final String? stackOverflowUrl;
  final String? leetcodeUrl;
  final String? codeforcesUrl;
  final String? gitlabUrl;
  final String? hackerRankUrl;
  final String? behanceUrl;
  final String? otherUrl;

  const ProfileLinks({
    this.linkedinUrl,
    this.githubUrl,
    this.twitterUrl,
    this.personalWebsite,
    this.stackOverflowUrl,
    this.leetcodeUrl,
    this.codeforcesUrl,
    this.gitlabUrl,
    this.hackerRankUrl,
    this.behanceUrl,
    this.otherUrl,
  });

  static const empty = ProfileLinks();

  /// Reads the link fields off a `/work-details/me` payload. Blank strings are
  /// normalized to null so the UI treats them as unset.
  factory ProfileLinks.fromWorkDetails(Map<String, dynamic>? wd) {
    String? s(dynamic v) {
      final str = v?.toString().trim();
      return (str == null || str.isEmpty) ? null : str;
    }

    if (wd == null) return empty;
    return ProfileLinks(
      linkedinUrl: s(wd['linkedinUrl']),
      githubUrl: s(wd['githubUrl']),
      twitterUrl: s(wd['twitterUrl']),
      personalWebsite: s(wd['personalWebsite']),
      stackOverflowUrl: s(wd['stackOverflowUrl']),
      leetcodeUrl: s(wd['leetcodeUrl']),
      codeforcesUrl: s(wd['codeforcesUrl']),
      gitlabUrl: s(wd['gitlabUrl']),
      hackerRankUrl: s(wd['hackerRankUrl']),
      behanceUrl: s(wd['behanceUrl']),
      otherUrl: s(wd['otherUrl']),
    );
  }

  /// This profile's links as the raw column map, for round-tripping through
  /// [workLinksToProfileLinksPayload] (which diffs against it so untouched
  /// columns are never rewritten).
  Map<String, dynamic> get columns => {
        'linkedinUrl': linkedinUrl,
        'githubUrl': githubUrl,
        'twitterUrl': twitterUrl,
        'personalWebsite': personalWebsite,
        'stackOverflowUrl': stackOverflowUrl,
        'leetcodeUrl': leetcodeUrl,
        'codeforcesUrl': codeforcesUrl,
        'gitlabUrl': gitlabUrl,
        'hackerRankUrl': hackerRankUrl,
        'behanceUrl': behanceUrl,
        'otherUrl': otherUrl,
      };

  /// The links to display, as detected platforms.
  ///
  /// This is the profile-facing view and matches the website's
  /// `workLinksFromResumeDetails`: dedicated columns yield one chip each, and
  /// the multi-link columns (`personalWebsite`, `otherUrl`) are split so a
  /// designer's Figma/Dribbble/Behance links each render as their own platform
  /// rather than collapsing into one generic "Website" chip. Blocked links are
  /// filtered out, since the policy post-dates some stored data.
  List<WorkLink> get resolved => workLinksFromProfileFields(columns);

  bool get isEmpty => resolved.isEmpty;
}
