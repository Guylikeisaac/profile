import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/data/repository_exception.dart';
import '../../../core/network/api_client.dart';
import '../../post/data/models/post_models.dart'
    show Activity, ActivityResponse, UpdateVisibilityRequest;

/// Read/write access to the user Activity feed (post-service), verified
/// against the staging Swagger contract 2026-07-18:
///
///  • `GET  /api/post-service/activity/user/{userId}` — [userId] is the
///    internal auth **UUID** (never the public handle), `page` is 1-indexed,
///    `limit` maxes at 50, optional single-`type` filter. Visibility is
///    enforced server-side (owners see everything, others only PUBLIC).
///  • `DELETE /api/post-service/activity/{activityId}` — own activities only.
///  • `PATCH  /api/post-service/activity/{activityId}/visibility` — body
///    `{"visibility": "PUBLIC" | "PRIVATE"}`, own activities only.
///
/// Failures surface as [RepositoryException] with a clean user-facing message
/// (server `message` when present).
abstract interface class ActivityRepository {
  Future<ActivityResponse> loadUserActivities({
    required String userUuid,
    required int page,
    int limit,
    String? type,
  });

  Future<void> deleteActivity(String activityId);

  /// Returns the updated activity as the server now stores it.
  Future<Activity> setActivityVisibility({
    required String activityId,
    required String visibility,
  });
}

/// Server cap on `limit` is 50; the profile section pages in small chunks.
const int kActivityPageSize = 10;

class ApiActivityRepository implements ActivityRepository {
  ApiActivityRepository(this._client);

  final ApiClient _client;

  @override
  Future<ActivityResponse> loadUserActivities({
    required String userUuid,
    required int page,
    int limit = kActivityPageSize,
    String? type,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.post(ApiConstants.activityByUser(userUuid)),
        queryParams: {
          'page': page,
          'limit': limit,
          if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
        },
      );
      return ActivityResponse.fromJson(_dataOf(res.data));
    } on DioException catch (e) {
      throw RepositoryException(
        _serverMessage(e) ?? "We couldn't load this activity.",
        cause: e,
      );
    }
  }

  @override
  Future<void> deleteActivity(String activityId) async {
    try {
      await _client.delete(
        ApiConstants.post(ApiConstants.activityDelete(activityId)),
      );
    } on DioException catch (e) {
      throw RepositoryException(
        _serverMessage(e) ?? "Couldn't delete this activity.",
        cause: e,
      );
    }
  }

  @override
  Future<Activity> setActivityVisibility({
    required String activityId,
    required String visibility,
  }) async {
    try {
      final res = await _client.patch(
        ApiConstants.post(ApiConstants.activityUpdateVisibility(activityId)),
        data: UpdateVisibilityRequest(visibility: visibility).toJson(),
      );
      final data = _dataOf(res.data);
      final activity = data['activity'];
      return Activity.fromJson(
          activity is Map ? Map<String, dynamic>.from(activity) : const {});
    } on DioException catch (e) {
      throw RepositoryException(
        _serverMessage(e) ?? "Couldn't update this activity.",
        cause: e,
      );
    }
  }

  /// Unwraps the standard `{statusCode, message, success, data}` envelope.
  static Map<String, dynamic> _dataOf(dynamic body) {
    final data = body is Map ? body['data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  static String? _serverMessage(DioException e) {
    final data = e.response?.data;
    final message = data is Map ? data['message']?.toString().trim() : null;
    return (message == null || message.isEmpty) ? null : message;
  }
}
