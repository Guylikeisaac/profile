import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/data/repository_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/s3_uploader.dart';

/// Allowed image MIME types for profile picture / banner uploads (per backend).
const Set<String> kAllowedImageMimeTypes = {
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
};

/// Profile picture + banner media, on the auth-service.
///
/// Each upload is the documented three-step presigned flow:
///   1. `POST …/upload-url { fileName, mimeType }` → `{ uploadUrl, <key>, fileName }`
///   2. PUT the file bytes straight to S3 via [putFileToS3] (clean Dio — no
///      gateway auth header, which would break the presigned signature)
///   3. `PUT …/profile-picture { profilePicKey }` / `…/banner { bannerKey }`
///      to attach the stored key to the profile.
///
/// The key field names are exact (`profilePicKey`, `bannerKey`) — the backend
/// rejects a generic `key`. Deletes reset to the default / remove the banner.
class ProfileMediaRepository {
  ProfileMediaRepository(this._client);

  final ApiClient _client;

  // ── Profile picture ─────────────────────────────────────────────────────────

  Future<void> uploadProfilePicture({
    required String filePath,
    required String fileName,
    required String mimeType,
  }) async {
    await _uploadAndAttach(
      uploadUrlPath:
          ApiConstants.auth(ApiConstants.userProfilePictureUploadUrl),
      attachPath: ApiConstants.auth(ApiConstants.userProfilePicture),
      keyField: 'profilePicKey',
      filePath: filePath,
      fileName: fileName,
      mimeType: mimeType,
      action: 'update your photo',
    );
  }

  Future<void> deleteProfilePicture() async {
    try {
      await _client.delete(ApiConstants.auth(ApiConstants.userProfilePicture));
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'remove your photo'), cause: e);
    }
  }

  // ── Banner ───────────────────────────────────────────────────────────────────

  Future<void> uploadBanner({
    required String filePath,
    required String fileName,
    required String mimeType,
  }) async {
    await _uploadAndAttach(
      uploadUrlPath: ApiConstants.auth(ApiConstants.userBannerUploadUrl),
      attachPath: ApiConstants.auth(ApiConstants.userBanner),
      keyField: 'bannerKey',
      filePath: filePath,
      fileName: fileName,
      mimeType: mimeType,
      action: 'update your cover',
    );
  }

  Future<void> deleteBanner() async {
    try {
      await _client.delete(ApiConstants.auth(ApiConstants.userBanner));
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, 'remove your cover'), cause: e);
    }
  }

  // ── Shared presign → S3 → attach ─────────────────────────────────────────────

  Future<void> _uploadAndAttach({
    required String uploadUrlPath,
    required String attachPath,
    required String keyField,
    required String filePath,
    required String fileName,
    required String mimeType,
    required String action,
  }) async {
    try {
      final presign = await _client.post(
        uploadUrlPath,
        data: {'fileName': fileName, 'mimeType': mimeType},
      );
      final data = presign.data is Map ? (presign.data as Map)['data'] : null;
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      final uploadUrl = map?['uploadUrl']?.toString();
      final key = map?[keyField]?.toString();
      if (uploadUrl == null ||
          uploadUrl.isEmpty ||
          key == null ||
          key.isEmpty) {
        throw RepositoryException("Couldn't prepare the upload. Try again.");
      }

      await putFileToS3(
        uploadUrl: uploadUrl,
        filePath: filePath,
        contentType: mimeType,
      );

      await _client.put(attachPath, data: {keyField: key});
    } on DioException catch (e) {
      throw RepositoryException(_messageFor(e, action), cause: e);
    }
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
