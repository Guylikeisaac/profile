import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/data/repository_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/s3_uploader.dart';

/// A skill the user added under a category, e.g. (name: 'Figma',
/// category: 'DESIGN'). Matches the `/skill/create-batch` item shape.
class SkillInput {
  final String name;
  final String category;
  const SkillInput(this.name, this.category);
}

/// One language + proficiency, matching the `/work-details/languages` item
/// shape. [proficiency] must be one of the documented enum values
/// (Native · Professional · Intermediate · Conversational).
class LanguageInput {
  final String name;
  final String proficiency;
  const LanguageInput(this.name, this.proficiency);
}

/// A location result from `GET /resume-service/locations` — just the id and a
/// human label, which is all the pickers and `locationId` payloads need.
class LocationOption {
  final String id;
  final String label;
  const LocationOption(this.id, this.label);
}

/// Create/update payload for a work-experience record (`POST/PUT /experience`).
/// [workMode]/[locationType] are the documented enum values; dates serialize to
/// ISO-8601 as `startMonthYear`/`endMonthYear`.
class ExperienceInput {
  final String jobTitle;
  final String companyName;
  final String workMode;
  final String locationType;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool currentlyWorking;
  final String? jobDescription;
  final String? accentColorHex;
  final String? locationId;

  /// The company website already stored on the record, echoed back on update.
  ///
  /// The app has no input for this — it's website-only — but omitting the key
  /// does **not** leave it alone. `companyWebsite` is validated by a Zod chain
  /// that ends in `.transform()`, and a transform on an `.optional()` schema
  /// still runs when the key is missing, mapping `undefined` → `null`. The
  /// controller then writes that null because its guard only skips `undefined`.
  /// So a mobile edit that didn't send the key used to erase a website set on
  /// the web. Sending the value we read back is the fix.
  final String? companyWebsite;

  /// Skill ids for this role, or **null meaning "don't touch"**.
  ///
  /// This distinction is the whole safety mechanism. `usedSkills` is a
  /// full-replace on the server (`{set: [], connect: [...]}`), so a payload
  /// that always included the field would wipe the user's website-side
  /// selection on every unrelated mobile edit. Null omits the key entirely and
  /// leaves the relation as it was; an empty list is a deliberate "clear them
  /// all" and is sent.
  final List<String>? usedSkillIds;

  const ExperienceInput({
    required this.jobTitle,
    required this.companyName,
    required this.workMode,
    required this.locationType,
    required this.startDate,
    required this.endDate,
    required this.currentlyWorking,
    this.jobDescription,
    this.accentColorHex,
    this.locationId,
    this.companyWebsite,
    this.usedSkillIds,
  });

  /// Create payload. [companyWebsite] is omitted here — a brand-new record has
  /// no stored value to protect, and the app doesn't collect one.
  Map<String, dynamic> toJson() => {
        'jobTitle': jobTitle,
        'companyName': companyName,
        'workMode': workMode,
        'locationType': locationType,
        'currentlyWorking': currentlyWorking,
        if (startDate != null) 'startMonthYear': isoDateOnly(startDate!),
        if (!currentlyWorking && endDate != null)
          'endMonthYear': isoDateOnly(endDate!),
        if (jobDescription != null && jobDescription!.trim().isNotEmpty)
          'jobDescription': jobDescription!.trim(),
        if (accentColorHex != null) 'accentColor': accentColorHex,
        if (locationId != null && locationId!.isNotEmpty)
          'locationId': locationId,
        if (usedSkillIds != null) 'usedSkills': usedSkillIds,
      };

  /// Update payload: the create body plus the preserved `companyWebsite`.
  Map<String, dynamic> toUpdateJson() => {
        ...toJson(),
        'companyWebsite': companyWebsite,
      };
}

/// Create/update payload for an education record (`POST/PUT /education`).
class EducationInput {
  final String school;
  final String? degreeName;
  final String? fieldOfStudyName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? grade;
  final String? description;
  final String? accentColorHex;
  final String? locationId;

  const EducationInput({
    required this.school,
    this.degreeName,
    this.fieldOfStudyName,
    this.startDate,
    this.endDate,
    this.grade,
    this.description,
    this.accentColorHex,
    this.locationId,
  });

  /// Update (`PUT`) payload: only the keys the sheet actually filled, so an
  /// edit never blanks a field it doesn't own.
  Map<String, dynamic> toJson() => {
        'school': school,
        if (degreeName != null && degreeName!.trim().isNotEmpty)
          'degreeName': degreeName!.trim(),
        if (fieldOfStudyName != null && fieldOfStudyName!.trim().isNotEmpty)
          'fieldOfStudyName': fieldOfStudyName!.trim(),
        if (startDate != null) 'startDate': isoDateOnly(startDate!),
        if (endDate != null) 'endDate': isoDateOnly(endDate!),
        if (grade != null && grade!.trim().isNotEmpty) 'grade': grade!.trim(),
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        if (accentColorHex != null) 'accentColor': accentColorHex,
        if (locationId != null && locationId!.isNotEmpty)
          'locationId': locationId,
      };

  /// Create (`POST`) payload. Same seven always-present keys the web client
  /// sends, explicit `null`s included: `POST /education` answers a partial body
  /// with a 200 and a placeholder `school: "Unknown School"` row instead of a
  /// 400, so every key has to be on the wire. App-only extras stay conditional
  /// — web doesn't send them and they aren't part of the contract in question.
  Map<String, dynamic> toCreateJson() => {
        'school': school,
        'degreeName': _orNull(degreeName),
        'fieldOfStudyName': _orNull(fieldOfStudyName),
        'grade': _orNull(grade),
        'description': _orNull(description),
        'startDate': startDate == null ? null : isoDateOnly(startDate!),
        'endDate': endDate == null ? null : isoDateOnly(endDate!),
        if (accentColorHex != null) 'accentColor': accentColorHex,
        if (locationId != null && locationId!.isNotEmpty)
          'locationId': locationId,
      };

  static String? _orNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();
}

/// Serializes a picked calendar date as **UTC midnight of the same Y/M/D** so a
/// month-year choice round-trips. Using `date.toUtc()` would shift e.g. IST
/// "Jan 1 00:00" to "Dec 31 18:30Z", reading back as the previous month.
String isoDateOnly(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).toIso8601String();

/// Write paths for the structured profile sections that live on the user's
/// resume/work-details. Reads still flow through `ApiProfileRepository`
/// (`/work-details/me`); this is the create/replace side behind the profile
/// edit sheets, so a save round-trips and shows up on the profile after an
/// `invalidate(myProfileProvider)`.
///
/// Covers Skills, Languages, Experience and Education writes. Projects still
/// need the S3 presign flow before they can be wired here.
class ResumeSectionsRepository {
  ResumeSectionsRepository(this._client, {this.onHiringSignalChanged});

  final ApiClient _client;

  /// Fired after a successful mutation of hiring-relevant data (skills /
  /// experience — the Job Readiness Sprint's re-trigger signals). Injected by
  /// the provider so this repo stays decoupled from the sprint feature.
  final void Function()? onHiringSignalChanged;

  void _hiringSignalChanged() {
    try {
      onHiringSignalChanged?.call();
    } catch (_) {
      // The signal must never break the edit that fired it.
    }
  }

  // ── Skill categories (autocomplete) ────────────────────────────────────────

  /// Prefix-autocomplete for skill categories (`GET /skill/categories`,
  /// returns up to 5). There is no "list all categories" endpoint, so the add
  /// form pairs this with a free-text fallback. Returns `[]` on any failure so
  /// the form degrades to manual entry rather than erroring.
  Future<List<String>> searchSkillCategories(String query) async {
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.skillCategories),
        queryParams: {'category': query},
      );
      final data = res.data is Map ? (res.data as Map)['data'] : res.data;
      if (data is List) {
        return data
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
      return const [];
    } on DioException {
      return const [];
    }
  }

  // ── Locations ───────────────────────────────────────────────────────────────

  /// Searches the resume-service location catalogue for the location picker.
  /// Returns `[]` on failure so the picker shows "no results" rather than
  /// erroring.
  Future<List<LocationOption>> searchLocations(String query,
      {int limit = 12}) async {
    if (query.trim().isEmpty) return const [];
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.resumeLocations),
        queryParams: {'q': query.trim(), 'limit': limit},
      );
      final data = res.data is Map ? (res.data as Map)['data'] : res.data;
      if (data is! List) return const [];
      final out = <LocationOption>[];
      for (final item in data) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final label = item['label']?.toString().trim().isNotEmpty == true
            ? item['label'].toString()
            : [item['city'], item['state'], item['country']]
                .map((e) => e?.toString() ?? '')
                .where((e) => e.isNotEmpty)
                .join(', ');
        out.add(LocationOption(id, label.isEmpty ? id : label));
      }
      return out;
    } on DioException {
      return const [];
    }
  }

  // ── Experience ──────────────────────────────────────────────────────────────

  /// Creates a record and returns its new server id (so the still-open list can
  /// support an immediate edit/delete without a reload), or null if the
  /// response didn't surface one.
  Future<String?> createExperience(ExperienceInput input) async {
    try {
      final res = await _client.post(
        ApiConstants.resume(ApiConstants.experienceCreate),
        data: input.toJson(),
      );
      _hiringSignalChanged();
      return _newId(res.data);
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'add this experience'),
          cause: e);
    }
  }

  Future<void> updateExperience(String id, ExperienceInput input) async {
    try {
      await _client.put(
        ApiConstants.resume(ApiConstants.experienceUpdate(id)),
        data: input.toUpdateJson(),
      );
      _hiringSignalChanged();
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'save this experience'),
          cause: e);
    }
  }

  Future<void> deleteExperience(String id) async {
    try {
      await _client.delete(
        ApiConstants.resume(ApiConstants.experienceDelete(id)),
      );
      _hiringSignalChanged();
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'remove this experience'),
          cause: e);
    }
  }

  // ── Education ────────────────────────────────────────────────────────────────

  Future<String?> createEducation(EducationInput input) async {
    try {
      final res = await _client.post(
        ApiConstants.resume(ApiConstants.educationCreate),
        data: input.toCreateJson(),
      );
      return _newId(res.data);
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'add this education'), cause: e);
    }
  }

  Future<void> updateEducation(String id, EducationInput input) async {
    try {
      await _client.put(
        ApiConstants.resume(ApiConstants.educationUpdate(id)),
        data: input.toJson(),
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'save this education'),
          cause: e);
    }
  }

  Future<void> deleteEducation(String id) async {
    try {
      await _client.delete(
        ApiConstants.resume(ApiConstants.educationDelete(id)),
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'remove this education'),
          cause: e);
    }
  }

  /// Adds skills in one call. `category` is sent as-is; the read side
  /// (`/work-details/me`) groups by `categoryName`, so a created skill shows
  /// up under the same header after a refresh. No-op on an empty list.
  Future<void> addSkills(List<SkillInput> skills) async {
    if (skills.isEmpty) return;
    try {
      await _client.post(
        ApiConstants.resume(ApiConstants.resumeCreateSkillBatch),
        data: {
          'skills': [
            for (final s in skills) {'name': s.name, 'category': s.category},
          ],
        },
      );
      _hiringSignalChanged();
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'add your skills'), cause: e);
    }
  }

  /// Removes skills by name (the documented delete is name-keyed). No-op on an
  /// empty list.
  Future<void> deleteSkills(List<String> names) async {
    if (names.isEmpty) return;
    try {
      await _client.post(
        ApiConstants.resume(ApiConstants.resumeDeleteSkillBatch),
        data: {'names': names},
      );
      _hiringSignalChanged();
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'remove a skill'), cause: e);
    }
  }

  // ── Profile links (typed social/portfolio URLs) ──────────────────────────────

  /// Updates the typed profile links. [fields] carries only the keys the user
  /// changed (values are the URL, or an explicit `null` to clear that link) —
  /// omitted keys are preserved server-side (partial update). No-op when empty.
  Future<void> updateProfileLinks(Map<String, String?> fields) async {
    if (fields.isEmpty) return;
    try {
      await _client.put(
        ApiConstants.resume(ApiConstants.resumeProfileLinks),
        data: fields,
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'save your links'), cause: e);
    }
  }

  // ── Profile theme (solid banner colour) ──────────────────────────────────────

  /// Persists the profile banner colour as a solid `#RRGGBB` hex. The backend
  /// only supports a solid colour (no gradient), so gradient UI presets must map
  /// to one saved colour here.
  Future<void> updateProfileBannerColor(String hex) async {
    try {
      await _client.put(
        ApiConstants.resume(ApiConstants.resumeProfileTheme),
        data: {'profileBannerColor': hex},
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'save your cover colour'),
          cause: e);
    }
  }

  /// Persists per-category skill accent colours as `{category: '#RRGGBB'}` on
  /// the profile theme. Send the full desired map (the backend keys colours by
  /// category name). No-op on an empty map.
  Future<void> updateSkillCategoryColors(Map<String, String> colors) async {
    if (colors.isEmpty) return;
    try {
      await _client.put(
        ApiConstants.resume(ApiConstants.resumeProfileTheme),
        data: {'skillCategoryAccentColors': colors},
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'save your skill colours'),
          cause: e);
    }
  }

  // ── Intro media (audio/video) ────────────────────────────────────────────────

  /// Presigns, uploads to S3, and saves an intro audio/video in one call.
  /// Returns the saved media URL. [mediaType] is `audio` or `video`.
  Future<String> uploadIntroMedia({
    required String filePath,
    required String mediaType,
    required String extension,
    required String contentType,
    bool isPublic = false,
  }) async {
    try {
      final presign = await _client.get(
        ApiConstants.resume(ApiConstants.resumeIntroMediaUploadUrl),
        queryParams: {
          'mediaType': mediaType,
          'extension': extension,
          'contentType': contentType,
        },
      );
      final data = presign.data is Map ? (presign.data as Map)['data'] : null;
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      final uploadUrl =
          (map?['uploadUrl'] ?? map?['url'] ?? map?['signedUrl'])?.toString();
      if (uploadUrl == null || uploadUrl.isEmpty) {
        throw const RepositoryException("Couldn't prepare the media upload.");
      }
      await putFileToS3(
        uploadUrl: uploadUrl,
        filePath: filePath,
        contentType: contentType,
      );
      // The saved reference is the public object URL (the presigned URL minus
      // its signature query), or an explicit key/publicUrl if the gateway
      // returns one.
      final saved =
          (map?['publicUrl'] ?? map?['fileUrl'] ?? map?['key'])?.toString() ??
              uploadUrl.split('?').first;
      await _client.put(
        ApiConstants.resume(ApiConstants.resumeIntroMedia),
        data: {
          'introMediaUrl': saved,
          'introMediaType': mediaType,
          'introMediaPublic': isPublic,
        },
      );
      return saved;
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'upload your intro video'),
          cause: e);
    }
  }

  Future<void> deleteIntroMedia() async {
    try {
      await _client.delete(ApiConstants.resume(ApiConstants.resumeIntroMedia));
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'remove your intro video'),
          cause: e);
    }
  }

  Future<void> setIntroMediaVisibility(bool isPublic) async {
    try {
      await _client.patch(
        ApiConstants.resume(ApiConstants.resumeIntroMediaVisibility),
        data: {'introMediaPublic': isPublic},
      );
    } on DioException catch (e) {
      throw RepositoryException(
          _messageFor(e, 'update your intro video visibility'),
          cause: e);
    }
  }

  /// Replaces the entire language list — the endpoint is a whole-list PUT, so
  /// the caller must send the final desired set (adds, edits and deletes all
  /// collapse into this one call).
  Future<void> replaceLanguages(List<LanguageInput> languages) async {
    try {
      await _client.put(
        ApiConstants.resume(ApiConstants.resumeLanguages),
        data: {
          'languages': [
            for (final l in languages)
              {'name': l.name, 'proficiency': l.proficiency},
          ],
        },
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'save your languages'),
          cause: e);
    }
  }

  /// Pulls the created record's id out of a `{data: {...}}` create response,
  /// tolerant of `id`/`_id`/`experienceId`/`educationId`. Null if absent.
  static String? _newId(dynamic body) {
    final data = (body is Map && body['data'] is Map)
        ? body['data'] as Map
        : (body is Map ? body : null);
    if (data == null) return null;
    final id = data['id'] ??
        data['_id'] ??
        data['experienceId'] ??
        data['educationId'];
    final s = id?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  String _messageFor(DioException e, String action) {
    final data = e.response?.data;
    final serverMsg = data is Map ? data['message']?.toString() : null;
    if (e.response?.statusCode == 401) {
      return 'Please sign in again to $action.';
    }
    return serverMsg ??
        "Couldn't $action. Check your connection and try again.";
  }
}
