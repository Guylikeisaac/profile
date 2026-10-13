import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/data/api_error_message.dart';
import '../../../core/data/repository_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/s3_uploader.dart';
import 'models/certification.dart';

/// A proof document the user picked locally, on its way to S3.
///
/// [sizeBytes] and [contentType] are validated *before* the presign call —
/// the backend rejects an oversized or unsupported file at `upload-url` time,
/// and burning a round trip (plus a signature) to learn that is worse than
/// telling the user immediately.
class CertificationDocument {
  final String filePath;
  final String fileName;
  final int sizeBytes;
  final String contentType;

  const CertificationDocument({
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
    required this.contentType,
  });

  String get extension {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return 'pdf';
    return fileName.substring(dot + 1).toLowerCase();
  }
}

/// The document rules the resume-service enforces on `certifications/*`.
///
/// Mirrored here so the sheet can fail fast with the same verdict the server
/// would give. Kept as plain statics (no Flutter imports) so they are directly
/// unit-testable.
class CertificationDocumentRules {
  static const int maxBytes = 10 * 1024 * 1024; // 10 MB

  /// Exactly the server's `ALLOWED_MIME_TYPES` set — note it lists both
  /// `image/jpeg` and the non-standard `image/jpg`.
  static const Set<String> allowedMimeTypes = {
    'application/pdf',
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };

  static const List<String> allowedExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  /// Best-effort MIME for a picked file. `file_picker` does not report one on
  /// every platform, so the extension is the reliable source.
  static String mimeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return '';
    }
  }

  /// Returns a user-facing reason the file can't be used, or null when it's
  /// acceptable.
  static String? validate(
      {required int sizeBytes, required String contentType}) {
    if (!allowedMimeTypes.contains(contentType)) {
      return 'Attach a PDF, JPG, PNG or WEBP file.';
    }
    if (sizeBytes > maxBytes) {
      return 'That file is larger than 10 MB. Please choose a smaller one.';
    }
    return null;
  }
}

/// Create/update payload for a certification.
///
/// The three document fields are modelled as an explicit [documentChange] so
/// an edit can express all three intents the backend distinguishes: leave the
/// existing document alone (omit the keys), attach a new one (send the key),
/// or detach (send an explicit null).
class CertificationInput {
  final String name;
  final String? issuingOrganization;
  final DateTime? issueDate;
  final DateTime? expirationDate;
  final String? credentialId;
  final String? credentialUrl;

  const CertificationInput({
    required this.name,
    this.issuingOrganization,
    this.issueDate,
    this.expirationDate,
    this.credentialId,
    this.credentialUrl,
  });

  /// Body for both create and update.
  ///
  /// Every field the sheet owns is sent explicitly — `null` where the user
  /// left it blank — because the sheet holds the complete record: an omitted
  /// key would silently keep a value the user just cleared.
  ///
  /// Dates go out as **full ISO-8601 timestamps**, not date-only strings: the
  /// schema validates them with Zod's `.datetime()`, which rejects `2026-01-31`
  /// outright. UTC midnight of the picked day keeps the calendar date stable
  /// (the same reason `isoDateOnly` exists for experience/education).
  Map<String, dynamic> toJson({
    String? documentKey,
    String? documentName,
    String? mimeType,
    bool documentChange = false,
  }) =>
      {
        'name': name.trim(),
        'issuingOrganization': _orNull(issuingOrganization),
        'issueDate': _isoOrNull(issueDate),
        'expirationDate': _isoOrNull(expirationDate),
        'credentialId': _orNull(credentialId),
        'credentialUrl': _orNull(credentialUrl),
        if (documentChange) ...{
          'documentKey': documentKey,
          'documentName': documentName,
          'mimeType': mimeType,
        },
      };

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? _isoOrNull(DateTime? date) => date == null
      ? null
      : DateTime.utc(date.year, date.month, date.day).toIso8601String();
}

/// Owner-side certifications on the resume-service, plus the presigned proof
/// upload.
///
/// Deliberately does NOT touch `certifications/internal/*` — those admin
/// review routes sit in front of the service's auth middleware and are not
/// something a user-facing client should ever call.
class CertificationsRepository {
  CertificationsRepository(this._client);

  final ApiClient _client;

  /// The signed-in user's certifications, newest submission first (the server
  /// already orders them).
  Future<List<Certification>> getMine() async {
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.certificationsMe),
      );
      return Certification.listFromResponse(res.data);
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'load your certifications'),
          cause: e);
    }
  }

  /// Another user's VERIFIED certifications.
  ///
  /// [userUuid] must be the internal auth UUID (`UserProfile.id`) — this route
  /// matches the stored id verbatim and does not resolve an `@handle`.
  Future<List<PublicCertification>> getPublic(String userUuid) async {
    if (userUuid.trim().isEmpty) return const [];
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.certificationsPublic(userUuid.trim())),
      );
      return PublicCertification.listFromResponse(res.data);
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'load these certifications'),
          cause: e);
    }
  }

  /// Presigns and uploads [document], returning the stored S3 key.
  ///
  /// The key is namespaced `certification/{userId}/…` by the server and is
  /// re-checked against the caller on create/update, so a key from this call
  /// is the only one the API will accept.
  Future<String> uploadDocument(CertificationDocument document) async {
    final reason = CertificationDocumentRules.validate(
      sizeBytes: document.sizeBytes,
      contentType: document.contentType,
    );
    if (reason != null) throw RepositoryException(reason);

    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.certificationsUploadUrl),
        queryParams: {
          'extension': document.extension,
          'contentType': document.contentType,
          'contentLength': document.sizeBytes,
        },
      );
      final target = _parseUpload(res.data);
      if (target == null) {
        throw const RepositoryException(
            "Couldn't prepare the document upload.");
      }
      // The content type MUST match the one the URL was signed with, or S3
      // answers 403 — see the note on [putFileToS3].
      await putFileToS3(
        uploadUrl: target.$1,
        filePath: document.filePath,
        contentType: document.contentType,
      );
      return target.$2;
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'upload the document'),
          cause: e);
    }
  }

  /// Creates a certification, uploading [document] first when one was picked.
  ///
  /// The order is load-bearing: the record must carry the S3 key, so the PUT
  /// to S3 has to complete before the create call goes out. A failed upload
  /// therefore leaves no half-made record behind.
  Future<Certification?> create(
    CertificationInput input, {
    CertificationDocument? document,
  }) async {
    String? key;
    if (document != null) key = await uploadDocument(document);
    try {
      final res = await _client.post(
        ApiConstants.resume(ApiConstants.certificationCreate),
        data: input.toJson(
          documentKey: key,
          documentName: document?.fileName,
          mimeType: document?.contentType,
          documentChange: document != null,
        ),
      );
      return _single(res.data);
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'add this certification'),
          cause: e);
    }
  }

  /// Updates a certification.
  ///
  /// [document] attaches a replacement; [removeDocument] detaches the current
  /// one. Passing neither leaves the stored document untouched — the three
  /// document keys are omitted entirely in that case.
  ///
  /// Note for callers: the backend sends the row back for review (status →
  /// PENDING) whenever it was previously VERIFIED or REJECTED, or whenever a
  /// new document is attached. See [Certification.editResetsVerification].
  Future<Certification?> update(
    String id,
    CertificationInput input, {
    CertificationDocument? document,
    bool removeDocument = false,
  }) async {
    String? key;
    if (document != null) key = await uploadDocument(document);
    final changingDocument = document != null || removeDocument;
    try {
      final res = await _client.put(
        ApiConstants.resume(ApiConstants.certificationUpdate(id)),
        data: input.toJson(
          documentKey: key,
          documentName: document?.fileName,
          mimeType: document?.contentType,
          documentChange: changingDocument,
        ),
      );
      return _single(res.data);
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'save this certification'),
          cause: e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.delete(
        ApiConstants.resume(ApiConstants.certificationDelete(id)),
      );
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'remove this certification'),
          cause: e);
    }
  }

  static Certification? _single(dynamic body) {
    final data = (body is Map && body['data'] is Map) ? body['data'] : body;
    if (data is! Map) return null;
    return Certification.fromJson(Map<String, dynamic>.from(data));
  }

  /// `(uploadUrl, key)` from the presign response. The documented shape is
  /// `{data: {uploadUrl, s3Key}}`; the aliases mirror [ProjectsRepository] so
  /// a gateway that renames the key doesn't silently break the upload.
  static (String, String)? _parseUpload(dynamic body) {
    final data = (body is Map && body['data'] is Map) ? body['data'] : body;
    if (data is! Map) return null;
    final url =
        (data['uploadUrl'] ?? data['url'] ?? data['signedUrl'])?.toString();
    final key =
        (data['s3Key'] ?? data['key'] ?? data['documentKey'])?.toString();
    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return (url, key);
  }

  String _messageFor(DioException e, String action) =>
      apiErrorMessage(e, action);
}
