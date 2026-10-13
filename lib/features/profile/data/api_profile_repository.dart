import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/data/repository_exception.dart';
import '../../../core/network/api_client.dart';
import 'experience_ordering.dart';
import 'models/profile_edit.dart';
import 'models/profile_links.dart';
import 'models/user_profile.dart';
import 'profile_repository.dart';

/// API-backed [ProfileRepository] for the current user.
///
/// The whole profile is two GETs through the authenticated [ApiClient] (auth
/// rides the `apiClientProvider` interceptor — no manual token reads). Both are
/// the documented Profile-API read routes (see the Profile Notion + gateway
/// Swagger): there is intentionally NO `?userId=` query form for work-details —
/// only `/work-details/me` (mine) and `/work-details/public/{userId}` (others).
///   1. `GET /api/auth-service/auth/session` for identity (name, title,
///      picture, bio, the userId slug).
///   2. `GET /api/resume-service/resume/work-details/me` which embeds company,
///      location, links, key skills, categorized skills, experience, education,
///      and languages — onboarding writes all of this, so this is the read side
///      of the onboarding "carry-forward".
///
/// Envelope for both: `{ statusCode, message, data: {...}, success }`.
///
/// [updateProfile] persists only the Edit Profile fields that have a documented
/// write route, and only those the user actually changed: name + title via
/// `PUT /api/auth-service/user`, bio via `/user/bio`, and company /
/// personal-website / job-seeking-status via the `/resume/work-details/*` PUTs.
/// Location (the documented route needs a `locationId` the free-text field can't
/// supply) and Handle (no documented write) are intentionally NOT written. Any
/// attempted write that fails is surfaced as an error, so the UI only reports
/// success when the change actually persisted.
class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._client);

  final ApiClient _client;

  /// Optimistic overlay for the two identity scalars (`name`, `userTitle`) that
  /// lag on `/auth/session` right after a `PUT /user`: the session keeps echoing
  /// the pre-edit values for a few seconds. We remember what we just wrote so
  /// [getMyProfile] reflects the edit immediately (the Edit Profile form + hero
  /// seed from it), then clear each field the moment the session catches up.
  /// Only set on a *successful* write, so a rejected edit never "sticks".
  String? _pendingName;
  String? _pendingTitle;
  String? _staleSessionNameBeforePending;
  String? _staleSessionTitleBeforePending;
  String? _lastSessionName;
  String? _lastSessionTitle;

  /// The raw `work-details.currentCompany` scalar as the server last returned
  /// it for *my* profile. [_buildProfile] no longer surfaces this value (it
  /// derives the company from the experience rows instead), but Save still
  /// needs it to tell "the user changed the company" apart from "the server's
  /// copy has drifted and should be repaired". Null until a read has happened.
  String? _serverCurrentCompany;

  @override
  Future<UserProfile> getMyProfile() async {
    try {
      // Identity from the documented session endpoint.
      final session = await _client.get(
        ApiConstants.auth(ApiConstants.authSession),
      );
      final user = _dataOf(session.data)?['user'];
      if (user is! Map) {
        throw const RepositoryException('Could not load your profile.');
      }
      final u = Map<String, dynamic>.from(user);

      // My resume/work details from the documented "my work details" route.
      // Failures are NOT swallowed: a DioException propagates (below) so the UI
      // shows an error/retry rather than a misleading half-profile. A 200 whose
      // `data` is empty is a legitimate "no resume yet" state, not a failure —
      // `_buildProfile` renders an identity-only profile for it.
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.resumeWorkDetailsMe),
      );
      final wd = _dataOf(res.data);
      _serverCurrentCompany = wd?['currentCompany']?.toString() ?? '';

      // Projects live on a separate route (not embedded in work-details). A
      // failure here must NOT sink the whole profile, so it degrades to an
      // empty projects list.
      final projects = await _fetchProjects();

      // `/auth/session` now includes `banner` (verified on staging 2026-07-03;
      // it used to omit it). Prefer it, and keep the public-profile fetch only
      // as a fallback for gateways that still omit it — the fallback also
      // tracks a self profile-view, so skipping it when possible matters.
      final banner = _nonEmpty(u['banner']) ??
          await _fetchBanner(u['userId']?.toString() ?? '');

      // Clear each pending overlay field once the session has caught up to the
      // value we wrote; otherwise keep overriding the stale session identity.
      final sessionName = u['name']?.toString() ?? '';
      final sessionTitle = u['userTitle']?.toString() ?? '';
      _lastSessionName = sessionName;
      _lastSessionTitle = sessionTitle;
      _reconcilePendingIdentity(
        sessionName: sessionName,
        sessionTitle: sessionTitle,
      );

      return _buildProfile(
        u,
        wd,
        projects,
        banner: banner,
        overrideName: _pendingName,
        overrideTitle: _pendingTitle,
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e), cause: e);
    }
  }

  @override
  Future<UserProfile> getPublicProfile(String handle) async {
    if (handle.isEmpty) {
      throw const RepositoryException('Could not load this profile.');
    }
    try {
      // Identity — the public endpoint takes the custom handle (a UUID 404s) and
      // returns the full user object (incl. banner) directly under `data`.
      final userRes = await _client.get(
        ApiConstants.auth(ApiConstants.userPublicProfile(handle)),
      );
      final data = _dataOf(userRes.data);
      final u = data?['user'] is Map
          ? Map<String, dynamic>.from(data!['user'] as Map)
          : (data ?? <String, dynamic>{});
      if (u.isEmpty) {
        throw const RepositoryException('This profile could not be found.');
      }

      // Public work-details embeds experience/education/skills/languages just
      // like /me (verified), and public projects live on their own route. Both
      // are non-fatal so a thin profile still renders.
      Map<String, dynamic>? wd;
      try {
        final wdRes = await _client.get(
          ApiConstants.resume(ApiConstants.resumeWorkDetailsPublic(handle)),
        );
        wd = _dataOf(wdRes.data);
      } on DioException {
        wd = null;
      }
      final projects = await _fetchPublicProjects(handle);

      return _buildProfile(u, wd, projects, banner: _nonEmpty(u['banner']));
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e), cause: e);
    }
  }

  Future<List<ProjectEntry>> _fetchPublicProjects(String handle) async {
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.projectsAllByUser(handle)),
      );
      final body = res.data;
      final raw = (body is Map && body['data'] is List)
          ? body['data']
          : (body is List ? body : null);
      return _mapList(raw, _mapProject);
    } on DioException {
      return const [];
    }
  }

  /// Fallback banner read from the public-profile endpoint, for sessions that
  /// don't carry `banner` (older gateway builds). Non-fatal → null on failure.
  Future<String?> _fetchBanner(String slug) async {
    if (slug.isEmpty) return null;
    try {
      final res = await _client.get(
        ApiConstants.auth(ApiConstants.userPublicProfile(slug)),
      );
      final data = res.data;
      final map = (data is Map && data['data'] is Map)
          ? Map<String, dynamic>.from(data['data'] as Map)
          : null;
      if (map == null) return null;
      final nested = map['user'];
      final banner = map['banner'] ?? (nested is Map ? nested['banner'] : null);
      return _nonEmpty(banner);
    } on DioException {
      return null;
    }
  }

  /// Fetches `GET /projects/all` and maps it, swallowing failures to `[]` so a
  /// projects outage never breaks the rest of the profile.
  Future<List<ProjectEntry>> _fetchProjects() async {
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.projectsAll),
      );
      final body = res.data;
      final raw = (body is Map && body['data'] is List)
          ? body['data']
          : (body is List ? body : null);
      return _mapList(raw, _mapProject);
    } on DioException {
      return const [];
    }
  }

  @override
  Future<UserProfile> updateProfile(ProfileEdit edit) async {
    // Diff against current server state so we only write what changed (and never
    // re-write seeded values, e.g. a placeholder bio). Location and Handle are
    // intentionally skipped — see the class doc.
    final current = await getMyProfile();
    final failures = <String>[];

    // Name + Title share one route; send both so neither is dropped regardless
    // of replace-vs-merge semantics on the server. The live endpoint also
    // requires `profilePic` in the body (returns 400 "profilePic: Required"
    // otherwise — the Swagger schema lists it but doesn't flag it optional), so
    // re-send the current picture unchanged. Note: the server validates
    // name/userTitle as alphabetic (rejects digits).
    if (edit.name != current.name || edit.headline != current.title) {
      final failedBefore = failures.length;
      await _putField(
        ApiConstants.auth(ApiConstants.userUpdate),
        {
          'name': edit.name,
          'userTitle': edit.headline,
          'profilePic': current.profilePic,
        },
        'Name/Title',
        failures,
      );
      // Write persisted → remember it so reads reflect the new name/title
      // immediately, even while `/auth/session` still returns the pre-edit
      // identity. Skipped if the PUT failed (it landed in `failures`).
      if (failures.length == failedBefore) {
        _pendingName = edit.name;
        _pendingTitle = edit.headline;
        _staleSessionNameBeforePending = _lastSessionName ?? current.name;
        _staleSessionTitleBeforePending = _lastSessionTitle ?? current.title;
      }
    }
    if (edit.about != current.about) {
      await _putField(
        ApiConstants.auth(ApiConstants.userUpdateBio),
        {'bio': edit.about},
        'Bio',
        failures,
      );
    }
    // Compared against the *server's* scalar rather than `current.company`,
    // which is now derived from the experience rows. That makes this branch do
    // double duty: it writes a genuine edit (accounts with no experience yet,
    // where the field is still free text), and it repairs the scalar when the
    // server's copy has drifted away from the real current role — which is the
    // state that had "Xero Apps" sitting in Basic Info while the timeline
    // correctly showed Codeaamy. Only ever fired by an explicit Save.
    if (edit.company.trim() !=
        (_serverCurrentCompany ?? current.company).trim()) {
      final failedBefore = failures.length;
      await _putField(
        ApiConstants.resume(ApiConstants.resumeUpdateCurrentCompany),
        {'currentCompany': edit.company},
        'Company',
        failures,
      );
      if (failures.length == failedBefore) {
        _serverCurrentCompany = edit.company;
      }
    }
    if (edit.website != current.website) {
      await _putField(
        ApiConstants.resume(ApiConstants.resumePersonalWebsite),
        {'personalWebsite': edit.website},
        'Website',
        failures,
      );
    }
    if (edit.openToWork != current.openToWork) {
      // The read derives openToWork from work-details.jobSeekingStatus, so this
      // (not /user/open-to, a separate WORK/HIRE field) is the route that
      // round-trips the toggle. ON = active, OFF = inactive.
      await _putField(
        ApiConstants.resume(ApiConstants.resumeUpdateJobSeekingStatus),
        {'jobSeekingStatus': edit.openToWork ? 'active' : 'inactive'},
        'Open to Work',
        failures,
      );
    }
    // Location now has a picker that supplies a real locationId; write it only
    // when the user actually chose one (null = unchanged).
    if (edit.locationId != null && edit.locationId!.isNotEmpty) {
      await _putField(
        ApiConstants.resume(ApiConstants.resumeCurrentLocation),
        {'locationId': edit.locationId},
        'Location',
        failures,
      );
    }

    // Partial persistence is allowed: earlier successes are kept. Surface any
    // failures so the UI never claims a clean save when something didn't persist.
    if (failures.isNotEmpty) {
      throw RepositoryException('Could not save: ${failures.join(', ')}.');
    }

    // Re-read authoritative state for the caller to render.
    return getMyProfile();
  }

  /// Reconciles the optimistic name/title overlay against the latest live
  /// session payload.
  ///
  /// There are three legitimate states after a successful `PUT /user`:
  /// 1. session still returns the pre-edit identity → keep the optimistic value
  /// 2. session catches up to the just-saved value → clear the optimistic value
  /// 3. session now returns some other authoritative value (for example the
  ///    user changed it again elsewhere) → clear the stale optimistic value
  void _reconcilePendingIdentity({
    required String sessionName,
    required String sessionTitle,
  }) {
    if (_pendingName != null) {
      if (sessionName == _pendingName ||
          (_staleSessionNameBeforePending != null &&
              sessionName != _staleSessionNameBeforePending)) {
        _pendingName = null;
        _staleSessionNameBeforePending = null;
      }
    }

    if (_pendingTitle != null) {
      if (sessionTitle == _pendingTitle ||
          (_staleSessionTitleBeforePending != null &&
              sessionTitle != _staleSessionTitleBeforePending)) {
        _pendingTitle = null;
        _staleSessionTitleBeforePending = null;
      }
    }
  }

  /// PUTs one documented field through the authenticated client. On failure it
  /// records [label] in [failures] instead of throwing, so the remaining fields
  /// still attempt (partial persistence).
  Future<void> _putField(
    String path,
    Map<String, dynamic> body,
    String label,
    List<String> failures,
  ) async {
    try {
      await _client.put(path, data: body);
    } on DioException {
      failures.add(label);
    }
  }

  // ── Mapping ────────────────────────────────────────────────────────────────

  UserProfile _buildProfile(
    Map<String, dynamic> u,
    Map<String, dynamic>? wd,
    List<ProjectEntry> projects, {
    String? banner,
    // Optimistic identity overlay (self only) — see [_pendingName]. Null falls
    // back to the session value; only the current user's read passes these.
    String? overrideName,
    String? overrideTitle,
  }) {
    final slug = u['userId']?.toString() ?? '';
    final jobStatus = wd?['jobSeekingStatus']?.toString();

    // Sorted once, here, so every surface that reads `UserProfile` — profile
    // page, edit screen, CV view, drawer, public view — gets the same order.
    // The server returns these unordered.
    final experiences =
        sortExperiencesNewestFirst(_mapList(wd?['experience'], _mapExperience));
    final educations =
        sortEducationsNewestFirst(_mapList(wd?['education'], _mapEducation));

    return UserProfile(
      id: u['id']?.toString() ?? '',
      userId: slug,
      name: overrideName ?? (u['name']?.toString() ?? ''),
      title: overrideTitle ?? (u['userTitle']?.toString() ?? ''),
      profilePic: u['profilePic']?.toString() ?? '',
      // Banner lives on the auth-service user (fetched from the public profile,
      // since the session omits it); a resolved URL or null when unset.
      banner: banner ?? _nonEmpty(u['banner']),
      location: wd?['currentLocation']?.toString(),
      // Derived from the experience rows, NOT read straight off the scalar —
      // see [canonicalCurrentCompany] for why the scalar can't be trusted.
      company: canonicalCurrentCompany(
        experiences,
        fallback: wd?['currentCompany']?.toString() ?? '',
      ),
      department: _nameOf(wd?['department']),
      industry: _nameOf(wd?['industry']),
      handle: slug.isEmpty ? '' : '@$slug',
      website: wd?['personalWebsite']?.toString() ?? '',
      about: u['bio']?.toString() ?? '',
      openToWork: jobStatus == 'active',
      impressionCount: (u['impressionCount'] as num?)?.toInt() ?? 0,
      experiences: experiences,
      educations: educations,
      skills: _stringList(wd?['keySkills']),
      categorizedSkills: _groupSkills(wd?['skills']),
      skillCatalog: _skillCatalog(wd?['skills']),
      languages: _mapList(wd?['languages'], _mapLanguage),
      // No clean backend source — the view supplies placeholders.
      technicalSkills: const [],
      projects: projects,
      links: ProfileLinks.fromWorkDetails(wd),
      bannerColor: _nonEmpty(wd?['profileBannerColor']),
      skillCategoryColors: _stringMap(wd?['skillCategoryAccentColors']),
      introMediaUrl: _nonEmpty(wd?['introMediaUrl']),
      introMediaType: _nonEmpty(wd?['introMediaType']),
      introMediaPublic: wd?['introMediaPublic'] == true,
    );
  }

  /// A `{category: hex}` colour map, keys uppercased to match the grouped skill
  /// categories. Non-map / empty input yields an empty map.
  static Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final key = k?.toString().trim().toUpperCase();
      final val = v?.toString().trim();
      if (key != null && key.isNotEmpty && val != null && val.isNotEmpty) {
        out[key] = val;
      }
    });
    return out;
  }

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Maps one project record (from `/projects/all`) into a display [ProjectEntry]
  /// carrying the raw fields the edit sheet round-trips. The tile subtitle is
  /// derived (year range, else the link host, else "Project") since the backend
  /// project has no separate "type" field.
  static ProjectEntry? _mapProject(Map<String, dynamic> p) {
    final title = p['title']?.toString() ?? '';
    if (title.isEmpty) return null;
    final start = _parseDate(p['startMonthYear']);
    final end = _parseDate(p['endMonthYear']);
    final currently = p['currentlyWorking'] == true;
    final linkUrl = _nonEmpty(p['linkUrl']);

    // The read returns attached media under `attachments[]` (each with
    // `imageKey` / `imageUrl` / `isCover`), not `attachmentKeys`. Collect the
    // keys (cover first) so an edit preserves the cover instead of dropping it.
    final keys = _attachmentKeys(p);

    return ProjectEntry(
      title: title,
      subtitle: _projectSubtitle(start, end, currently, linkUrl),
      id: _idOf(p) ?? _stringOrNull(p['projectId']),
      description: _nonEmpty(p['description']),
      linkUrl: linkUrl,
      additionalLinks: _stringList(p['additionalLinks']),
      coverUrl: _coverUrlOf(p),
      attachmentKeys: keys,
      currentlyWorking: currently,
      startDate: start,
      endDate: end,
      experienceId: _nonEmpty(p['experienceId']),
      sortOrder: p['sortOrder'] is num ? (p['sortOrder'] as num).toInt() : null,
    );
  }

  static String? _stringOrNull(dynamic v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Cover image URL: the project's top-level `imageUrl`, else the cover
  /// attachment's `imageUrl` (or the first attachment's), tolerant of a few
  /// legacy field spellings.
  static String? _coverUrlOf(Map<String, dynamic> p) {
    final direct = _nonEmpty(p['imageUrl']) ?? _nonEmpty(p['coverUrl']);
    if (direct != null) return direct;
    final cover = _coverAttachment(p);
    if (cover != null) {
      final url = _nonEmpty(cover['imageUrl']) ??
          _nonEmpty(cover['url']) ??
          _nonEmpty(cover['signedUrl']);
      if (url != null) return url;
    }
    return null;
  }

  /// Attachment S3 keys, cover first, from `attachments[].imageKey` (falling
  /// back to `attachmentKeys` if a future payload uses that shape).
  static List<String> _attachmentKeys(Map<String, dynamic> p) {
    final out = <String>[];
    final attachments = p['attachments'];
    if (attachments is List) {
      final sorted = attachments.whereType<Map>().toList()
        ..sort((a, b) =>
            (b['isCover'] == true ? 1 : 0) - (a['isCover'] == true ? 1 : 0));
      for (final a in sorted) {
        final key = _nonEmpty(a['imageKey']) ?? _nonEmpty(a['key']);
        if (key != null) out.add(key);
      }
    }
    if (out.isEmpty && p['attachmentKeys'] is List) {
      for (final k in p['attachmentKeys'] as List) {
        final s = _nonEmpty(k);
        if (s != null) out.add(s);
      }
    }
    return out;
  }

  /// The cover attachment (`isCover == true`), else the first attachment.
  static Map<String, dynamic>? _coverAttachment(Map<String, dynamic> p) {
    final attachments = p['attachments'];
    if (attachments is! List || attachments.isEmpty) return null;
    for (final a in attachments) {
      if (a is Map && a['isCover'] == true) {
        return Map<String, dynamic>.from(a);
      }
    }
    final first = attachments.first;
    return first is Map ? Map<String, dynamic>.from(first) : null;
  }

  static String _projectSubtitle(
      DateTime? start, DateTime? end, bool currently, String? linkUrl) {
    if (start != null) {
      final endLabel =
          currently ? 'Present' : (end != null ? '${end.year}' : '');
      return endLabel.isEmpty ? '${start.year}' : '${start.year}–$endLabel';
    }
    if (linkUrl != null) {
      final host = Uri.tryParse(linkUrl)?.host;
      if (host != null && host.isNotEmpty) return host.replaceFirst('www.', '');
    }
    return 'Project';
  }

  static List<T> _mapList<T>(
    dynamic raw,
    T? Function(Map<String, dynamic>) map,
  ) {
    if (raw is! List) return const [];
    final out = <T>[];
    for (final item in raw) {
      if (item is Map) {
        final mapped = map(Map<String, dynamic>.from(item));
        if (mapped != null) out.add(mapped);
      }
    }
    return out;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static ProfileEntry? _mapExperience(Map<String, dynamic> e) {
    final title = e['jobTitle']?.toString() ?? '';
    final company = e['companyName']?.toString() ?? '';
    if (title.isEmpty && company.isEmpty) return null;
    final currently = e['currentlyWorking'] == true;
    final desc = e['jobDescription']?.toString().trim() ?? '';
    return ProfileEntry(
      title: title,
      subtitle: company,
      meta: _formatRange(e['startMonthYear'], e['endMonthYear'], currently),
      trailingBadge: currently ? 'Now' : null,
      bullets: desc.isEmpty ? const [] : [desc],
      // Raw fields for the edit round-trip.
      id: _idOf(e),
      startDate: _parseDate(e['startMonthYear']),
      // Same invariant onboarding enforces: a current role carries no end date.
      // A contradictory row is normalised here rather than reaching the edit
      // sheet, where it would show a To value beside a ticked "I currently
      // work here".
      endDate: currently ? null : _parseDate(e['endMonthYear']),
      currentlyWorking: currently,
      accentColorHex: e['accentColor']?.toString(),
      locationId: _locationIdOf(e),
      locationLabel: _locationLabelOf(e),
      workMode: e['workMode']?.toString(),
      locationType: e['locationType']?.toString(),
      description: desc,
      // Read but never edited on mobile — carried so an edit can send it back
      // unchanged instead of letting the server null it out. See
      // [ProfileEntry.companyWebsite].
      companyWebsite: _nonEmpty(e['companyWebsite']),
      usedSkills: _skillCatalog(e['usedSkills']),
    );
  }

  static ProfileEntry? _mapEducation(Map<String, dynamic> e) {
    final school = e['school']?.toString() ?? '';
    if (school.isEmpty) return null;
    final degree = _nameOf(e['degree']).isNotEmpty
        ? _nameOf(e['degree'])
        : (e['degreeName']?.toString() ?? '');
    final field = _nameOf(e['fieldOfStudy']).isNotEmpty
        ? _nameOf(e['fieldOfStudy'])
        : (e['fieldOfStudyName']?.toString() ?? '');
    final subtitle = [degree, field].where((s) => s.isNotEmpty).join(' · ');
    final grade = e['grade']?.toString();
    return ProfileEntry(
      title: school,
      subtitle: subtitle,
      meta: _formatRange(e['startDate'], e['endDate'], false),
      trailingBadge: (grade == null || grade.isEmpty) ? null : grade,
      // Raw fields for the edit round-trip.
      id: _idOf(e),
      startDate: _parseDate(e['startDate']),
      endDate: _parseDate(e['endDate']),
      accentColorHex: e['accentColor']?.toString(),
      locationId: _locationIdOf(e),
      locationLabel: _locationLabelOf(e),
      degreeName: degree,
      fieldOfStudyName: field,
      grade: grade,
      description: e['description']?.toString(),
    );
  }

  /// Location id from a record, tolerant of a flat `locationId` or a nested
  /// `location` object.
  static String? _locationIdOf(Map<String, dynamic> m) {
    final flat = m['locationId']?.toString();
    if (flat != null && flat.isNotEmpty) return flat;
    final loc = m['location'];
    if (loc is Map) {
      final id = loc['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  /// Best-effort display label for a record's location ("City, State"), from a
  /// `location` object or a plain string. Null when there's nothing usable.
  static String? _locationLabelOf(Map<String, dynamic> m) {
    final loc = m['location'];
    if (loc is String) return loc.trim().isEmpty ? null : loc.trim();
    if (loc is Map) {
      final label = loc['label']?.toString();
      if (label != null && label.trim().isNotEmpty) return label.trim();
      final parts = [loc['city'], loc['state'], loc['country']]
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .join(', ');
      return parts.isEmpty ? null : parts;
    }
    return null;
  }

  static LanguageEntry? _mapLanguage(Map<String, dynamic> l) {
    final name = (l['name'] ?? l['language'])?.toString() ?? '';
    if (name.isEmpty) return null;
    final level = (l['level'] ?? l['proficiency'])?.toString() ?? '';
    final progress = l['progress'];
    return LanguageEntry(
      name: name,
      level: level,
      // The languages endpoint stores name + proficiency only (no numeric
      // progress), so derive the bar fill from the proficiency level instead
      // of leaving it at 0 — keeps the outer profile bars in step with the
      // edit sheet.
      progress:
          progress is num ? progress.toDouble() : _progressForLevel(level),
    );
  }

  /// Maps a proficiency level to a bar-fill fraction. Mirrors the edit sheet so
  /// the profile and the sheet show the same fill for a given level.
  static double _progressForLevel(String level) {
    switch (level.trim().toLowerCase()) {
      case 'native':
        return 1.0;
      case 'fluent':
        return 0.85;
      case 'professional':
        return 0.8;
      case 'intermediate':
        return 0.6;
      case 'conversational':
        return 0.45;
      default:
        return 0.55;
    }
  }

  static String? _idOf(Map<String, dynamic> m) {
    final id = m['id'] ?? m['_id'] ?? m['experienceId'] ?? m['educationId'];
    final s = id?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static DateTime? _parseDate(dynamic iso) {
    final raw = iso?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Groups `skills[]` (each `{name, categoryName}`) into the display map the
  /// Skills section expects, with uppercased category headers.
  /// The same `skills[]` payload as [_groupSkills], flattened and keeping each
  /// skill's **id** — which the per-experience picker needs to write
  /// `usedSkills`. Rows without an id are dropped: they can't be linked to a
  /// role, so offering them would produce a request the server rejects.
  static List<ProfileSkill> _skillCatalog(dynamic raw) {
    if (raw is! List) return const [];
    final out = <ProfileSkill>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty || !seen.add(id)) continue;
      out.add(ProfileSkill(
        id: id,
        name: name,
        category: item['categoryName']?.toString().trim().toUpperCase() ?? '',
      ));
    }
    return out;
  }

  static Map<String, List<String>> _groupSkills(dynamic raw) {
    if (raw is! List) return const {};
    final grouped = <String, List<String>>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final category =
          (item['categoryName']?.toString().trim().toUpperCase() ?? '');
      final key = category.isEmpty ? 'OTHER' : category;
      grouped.putIfAbsent(key, () => <String>[]).add(name);
    }
    return grouped;
  }

  static String _nameOf(dynamic ref) {
    if (ref is Map) return ref['name']?.toString() ?? '';
    return ref?.toString() ?? '';
  }

  /// "May 2026 – Present" / "Sep 2024 – Jun 2025". Returns null when there's no
  /// usable start date and the row isn't current.
  static String? _formatRange(dynamic start, dynamic end, bool currently) {
    final from = _monthYear(start);
    final to = currently ? 'Present' : _monthYear(end);
    if (from == null && to == null) return null;
    if (from == null) return to;
    if (to == null) return from;
    return '$from – $to';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String? _monthYear(dynamic iso) {
    final raw = iso?.toString();
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    return '${_months[dt.month - 1]} ${dt.year}';
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Map<String, dynamic>? _dataOf(dynamic body) {
    if (body is Map && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    return null;
  }

  String _messageFor(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final serverMsg = data is Map ? data['message']?.toString() : null;
    if (status == 401) {
      return serverMsg ?? 'Please sign in again to see your profile.';
    }
    return serverMsg ??
        'Could not load your profile. Check your connection and try again.';
  }
}
