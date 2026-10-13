import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/data/repository_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/s3_uploader.dart';
import 'resume_sections_repository.dart' show isoDateOnly;

/// Create/update payload for a project (`POST /projects`, `PUT /projects/{id}`),
/// matching the documented body. Dates serialize to UTC-midnight ISO via
/// [isoDateOnly] (same convention as Experience/Education).
/// One attachment on its way into a project, paired with the media kind the
/// server should record.
///
/// The schema's `attachmentKeys` preprocessor accepts a bare string too, but
/// coerces it to `mediaType: "image"` — so a video sent that way is stored
/// mislabelled and comes back with a null `imageUrl`. Always send the pair.
class ProjectAttachment {
  final String key;

  /// `image` or `video` — the server's `PROJECT_ATTACHMENT_MEDIA_TYPES`.
  final String mediaType;

  const ProjectAttachment(this.key, {this.mediaType = 'image'});

  Map<String, dynamic> toJson() => {'key': key, 'mediaType': mediaType};
}

/// How a Proof of Work entry is attributed. The website offers the same three
/// choices; only [experience] is a real backend field.
enum ProjectAssociation { experience, personal, freelance }

class ProjectInput {
  final String title;
  final String? description;
  final List<ProjectAttachment> attachments;
  final String? linkUrl;

  /// Up to [maxAdditionalLinks] extra URLs. Each must be absolute — the schema
  /// validates them with `new URL(...)`, which rejects a bare host.
  final List<String> additionalLinks;
  final bool currentlyWorking;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? experienceId;
  final int? sortOrder;

  /// Server cap (`PROJECT_ADDITIONAL_LINKS_MAX`).
  static const int maxAdditionalLinks = 5;

  /// Server caps, mirrored so the form can fail fast.
  static const int maxTitleLength = 80;
  static const int maxDescriptionLength = 500;

  const ProjectInput({
    required this.title,
    this.description,
    this.attachments = const [],
    this.linkUrl,
    this.additionalLinks = const [],
    this.currentlyWorking = false,
    this.startDate,
    this.endDate,
    this.experienceId,
    this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        'attachmentKeys': [for (final a in attachments) a.toJson()],
        if (linkUrl != null && linkUrl!.trim().isNotEmpty)
          'linkUrl': linkUrl!.trim(),
        'additionalLinks': additionalLinks,
        'currentlyWorking': currentlyWorking,
        if (startDate != null) 'startMonthYear': isoDateOnly(startDate!),
        if (!currentlyWorking && endDate != null)
          'endMonthYear': isoDateOnly(endDate!),
        if (experienceId != null && experienceId!.isNotEmpty)
          'experienceId': experienceId,
        if (sortOrder != null) 'sortOrder': sortOrder,
      };

  /// Applies the website's Personal / Freelance convention.
  ///
  /// Neither is a backend field: `experienceId` is a UUID or null, so the
  /// website encodes the distinction by clearing it and prefixing the
  /// description with `[Personal]` / `[Freelance]`. Mobile writes the same
  /// marker, or a project attributed on one platform would read as
  /// unattributed on the other.
  static ({String? experienceId, String? description}) applyAssociation({
    required ProjectAssociation association,
    required String? experienceId,
    required String? description,
  }) {
    final body = description?.trim();
    final text = (body == null || body.isEmpty) ? null : body;
    switch (association) {
      case ProjectAssociation.experience:
        return (experienceId: experienceId, description: text);
      case ProjectAssociation.personal:
        return (
          experienceId: null,
          description: text == null ? '[Personal]' : '[Personal]\n$text',
        );
      case ProjectAssociation.freelance:
        return (
          experienceId: null,
          description: text == null ? '[Freelance]' : '[Freelance]\n$text',
        );
    }
  }

  /// Reads the marker back off a stored description, so an edit re-opens on
  /// the choice the user made. Returns the association plus the description
  /// with the marker stripped.
  static ({ProjectAssociation association, String description}) readAssociation(
    String? description, {
    String? experienceId,
  }) {
    final raw = description ?? '';
    for (final (marker, value) in const [
      ('[Personal]', ProjectAssociation.personal),
      ('[Freelance]', ProjectAssociation.freelance),
    ]) {
      if (raw.startsWith(marker)) {
        return (
          association: value,
          description: raw.substring(marker.length).trimLeft(),
        );
      }
    }
    return (
      association: ProjectAssociation.experience,
      description: raw,
    );
  }
}

/// A presigned upload target for a project cover/image.
class ProjectUpload {
  final String uploadUrl;
  final String key;
  const ProjectUpload(this.uploadUrl, this.key);
}

/// Write + media paths for profile Projects, on the resume-service.
///
/// Reads still flow through `ApiProfileRepository` (`/projects/all`); this is
/// the create/update/delete + S3 cover-upload side behind the project sheet, so
/// a save round-trips onto the profile after an `invalidate(myProfileProvider)`.
class ProjectsRepository {
  ProjectsRepository(this._client);

  final ApiClient _client;

  /// Presigns a project cover, uploads the local [filePath] to S3, and returns
  /// the stored **key** to send in `attachmentKeys`.
  Future<String> uploadCover({
    required String filePath,
    required String extension,
    required String contentType,
    String mediaType = 'image',
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.projectsMediaUploadUrl),
        queryParams: {
          // The presign is media-type aware (`parseProjectMediaUploadParams`)
          // and echoes the kind back; sending it keeps the signed object and
          // the `attachmentKeys` entry describing the same bytes.
          'mediaType': mediaType,
          'extension': extension,
          'contentType': contentType,
        },
      );
      final target = _parseUpload(res.data);
      if (target == null) {
        throw const RepositoryException("Couldn't prepare the image upload.");
      }
      await putFileToS3(
        uploadUrl: target.uploadUrl,
        filePath: filePath,
        contentType: contentType,
      );
      return target.key;
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'upload the cover image'),
          cause: e);
    }
  }

  Future<String?> createProject(ProjectInput input) async {
    try {
      final res = await _client.post(
        ApiConstants.resume(ApiConstants.projectsCreate),
        data: input.toJson(),
      );
      return _newId(res.data);
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'add this project'), cause: e);
    }
  }

  Future<void> updateProject(String id, ProjectInput input) async {
    try {
      await _client.put(
        ApiConstants.resume(ApiConstants.projectUpdate(id)),
        data: input.toJson(),
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'save this project'), cause: e);
    }
  }

  Future<void> deleteProject(String id) async {
    try {
      await _client.delete(
        ApiConstants.resume(ApiConstants.projectDelete(id)),
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'remove this project'),
          cause: e);
    }
  }

  /// Pulls `{uploadUrl, key}` from a presign response, tolerant of the several
  /// field names the gateway may use for the S3 target and its key.
  static ProjectUpload? _parseUpload(dynamic body) {
    final maps = <Map<String, dynamic>>[];

    void collect(dynamic raw) {
      if (raw is! Map) return;
      final map = Map<String, dynamic>.from(raw);
      maps.add(map);
      if (map['data'] is Map) collect(map['data']);
      if (map['result'] is Map) collect(map['result']);
    }

    collect(body);
    for (final data in maps) {
      final url = (data['uploadUrl'] ??
              data['uploadURL'] ??
              data['url'] ??
              data['signedUrl'] ??
              data['signedURL'] ??
              data['presignedUrl'] ??
              data['presignedURL'])
          ?.toString();
      final key = (data['key'] ??
              data['s3Key'] ??
              data['fileKey'] ??
              data['attachmentKey'] ??
              data['objectKey'] ??
              data['mediaKey'] ??
              data['projectMediaKey'] ??
              data['projectImageKey'] ??
              data['projectCoverKey'] ??
              data['coverKey'] ??
              data['fileName'])
          ?.toString();
      if (url != null && url.isNotEmpty && key != null && key.isNotEmpty) {
        return ProjectUpload(url, key);
      }
    }
    return null;
  }

  static String? _newId(dynamic body) {
    final data = (body is Map && body['data'] is Map)
        ? body['data'] as Map
        : (body is Map ? body : null);
    if (data == null) return null;
    final id = data['id'] ?? data['_id'] ?? data['projectId'];
    final s = id?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  String _messageFor(DioException e, String action) {
    final data = e.response?.data;
    final serverMsg = data is Map ? data['message']?.toString() : null;
    final decoded = _decodeGatewayMessage(serverMsg);
    if (e.response?.statusCode == 401) {
      return 'Please sign in again to $action.';
    }
    return decoded ??
        serverMsg ??
        "Couldn't $action. Check your connection and try again.";
  }

  static String? _decodeGatewayMessage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final attachmentErrors = decoded['attachmentKeys'];
      if (attachmentErrors is Map && attachmentErrors['_errors'] is List) {
        final first = (attachmentErrors['_errors'] as List)
            .cast<dynamic>()
            .map((e) => e?.toString().trim() ?? '')
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty) return first;
      }
      if (decoded['_errors'] is List) {
        final first = (decoded['_errors'] as List)
            .cast<dynamic>()
            .map((e) => e?.toString().trim() ?? '')
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty) return first;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
