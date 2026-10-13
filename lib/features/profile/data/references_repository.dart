import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/data/api_error_message.dart';
import '../../../core/data/repository_exception.dart';
import '../../../core/network/api_client.dart';
import 'models/profile_reference.dart';

/// Thrown when a reference request is refused because the target declined a
/// previous one and the 10-day cooldown hasn't lapsed.
///
/// A dedicated type so the sheet can render the date with the app's own
/// formatting: the server's own sentence embeds a JS `toDateString()`
/// ("Sun Sep 14 2026"), which is not a format this app shows anywhere else.
class ReferenceCooldownException extends RepositoryException {
  final DateTime? canRequestAgainAt;

  const ReferenceCooldownException(super.message,
      {this.canRequestAgainAt, super.cause});
}

/// One row of the authenticated user-search, narrowed to what the reference
/// request picker needs.
class ReferenceSearchResult {
  /// Internal auth UUID.
  final String id;

  /// Public handle. This is what `POST /references` wants as `targetUserId`
  /// (the controller resolves a handle first, then falls back to a UUID), and
  /// it matches what the website sends.
  final String handle;
  final String name;
  final String title;
  final String profilePic;

  const ReferenceSearchResult({
    required this.id,
    required this.handle,
    required this.name,
    this.title = '',
    this.profilePic = '',
  });

  /// The identifier to send as `targetUserId`, preferring the handle and
  /// falling back to the UUID for a member who hasn't claimed one.
  String get targetUserId => handle.isNotEmpty ? handle : id;
}

/// Profile references between SyncUp members, on the resume-service.
///
/// Scope note: the service also exposes an unauthenticated
/// `references/submit/{token}` pair for the website's legacy
/// "email a stranger a link" flow. The app neither creates nor consumes those
/// — it only has to *display* rows the website left in `PENDING`.
class ReferencesRepository {
  ReferencesRepository(this._client);

  final ApiClient _client;

  /// Every reference row the signed-in user owns, in every status.
  Future<List<ProfileReference>> getMine() async {
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.referencesAll),
      );
      return ProfileReference.listFromResponse(res.data);
    } on DioException catch (e) {
      throw RepositoryException(apiErrorMessage(e, 'load your references'),
          cause: e);
    }
  }

  /// Requests other members have sent TO the signed-in user and are waiting on.
  Future<List<IncomingReferenceRequest>> getIncoming() async {
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.referencesIncoming),
      );
      return IncomingReferenceRequest.listFromResponse(res.data);
    } on DioException catch (e) {
      throw RepositoryException(apiErrorMessage(e, 'load reference requests'),
          cause: e);
    }
  }

  /// Approved references on a profile. [userIdOrHandle] accepts either form.
  Future<List<PublicProfileReference>> getPublic(String userIdOrHandle) async {
    final identifier = userIdOrHandle.trim();
    if (identifier.isEmpty) return const [];
    try {
      final res = await _client.get(
        ApiConstants.resume(ApiConstants.referencesPublic(identifier)),
      );
      return PublicProfileReference.listFromResponse(res.data);
    } on DioException catch (e) {
      throw RepositoryException(apiErrorMessage(e, 'load these references'),
          cause: e);
    }
  }

  /// Asks [targetUserId] (handle or UUID) for a reference.
  ///
  /// The four refusals the server distinguishes all reach the caller as a
  /// [RepositoryException] carrying the server's own sentence, except the
  /// cooldown — which arrives as a [ReferenceCooldownException] so the date
  /// can be re-formatted:
  ///
  ///   * 400 — asking yourself
  ///   * 404 — no such profile, **or** either side has blocked the other
  ///           (deliberately indistinguishable; don't try to tell them apart)
  ///   * 409 — a request with this person is already open
  ///   * 403 — they declined recently; `canRequestAgainAt` says when
  Future<void> requestReference({
    required String targetUserId,
    String? relationship,
  }) async {
    try {
      await _client.post(
        ApiConstants.resume(ApiConstants.referenceCreate),
        data: {
          'targetUserId': targetUserId.trim(),
          'relationship': _orNull(relationship),
        },
      );
    } on DioException catch (e) {
      final message = apiErrorMessage(e, 'send this request');
      if (e.response?.statusCode == 403) {
        throw ReferenceCooldownException(
          message,
          canRequestAgainAt: _cooldownFrom(e.response?.data),
          cause: e,
        );
      }
      throw RepositoryException(message, cause: e);
    }
  }

  /// Accepts an incoming request and writes the reference in one step.
  ///
  /// The result publishes immediately (status → APPROVED); there is no second
  /// approval by the requester. The author is taken from the session, so
  /// [reviewerTitle]/[reviewerCompany] are the only attribution the writer
  /// controls.
  Future<void> provideReference(
    String referenceId, {
    required String reviewText,
    String? reviewerTitle,
    String? reviewerCompany,
  }) async {
    try {
      await _client.post(
        ApiConstants.resume(ApiConstants.referenceProvide(referenceId)),
        data: {
          'reviewText': reviewText.trim(),
          'reviewerTitle': _orNull(reviewerTitle),
          'reviewerCompany': _orNull(reviewerCompany),
        },
      );
    } on DioException catch (e) {
      throw RepositoryException(apiErrorMessage(e, 'send this reference'),
          cause: e);
    }
  }

  /// Declines an incoming request. (The same route also lets an owner reject a
  /// legacy PENDING submission; both land here.)
  Future<void> rejectReference(String referenceId) async {
    try {
      await _client.post(
        ApiConstants.resume(ApiConstants.referenceReject(referenceId)),
      );
    } on DioException catch (e) {
      throw RepositoryException(apiErrorMessage(e, 'decline this request'),
          cause: e);
    }
  }

  /// Removes a reference the user owns. The server rejects this for a
  /// SyncUp-linked row that isn't APPROVED — see
  /// [ProfileReference.isDeletable], which the UI uses to hide the action.
  Future<void> deleteReference(String referenceId) async {
    try {
      await _client.delete(
        ApiConstants.resume(ApiConstants.referenceDelete(referenceId)),
      );
    } on DioException catch (e) {
      throw RepositoryException(apiErrorMessage(e, 'remove this reference'),
          cause: e);
    }
  }

  /// Name-prefix member search for the request picker.
  ///
  /// [excludeUserId] drops the signed-in user from the results — the server
  /// happily returns you to yourself, and the request endpoint then 400s. The
  /// filter is applied on both the UUID and the handle because callers may
  /// hold either.
  ///
  /// Returns `[]` on failure so the picker shows "no matches" rather than
  /// erroring mid-typing.
  Future<List<ReferenceSearchResult>> searchMembers(
    String query, {
    String? excludeUserId,
    String? excludeHandle,
    int limit = 10,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    try {
      final res = await _client.get(
        ApiConstants.auth(ApiConstants.userSearchUsers),
        queryParams: {'startsWith': term, 'limit': limit},
      );
      final data = res.data is Map ? (res.data as Map)['data'] : res.data;
      if (data is! List) return const [];
      final out = <ReferenceSearchResult>[];
      for (final row in data) {
        if (row is! Map) continue;
        final id = row['id']?.toString() ?? '';
        final handle = row['userId']?.toString() ?? '';
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        if (id.isNotEmpty && id == excludeUserId) continue;
        if (handle.isNotEmpty && handle == excludeHandle) continue;
        out.add(ReferenceSearchResult(
          id: id,
          handle: handle,
          name: name,
          title: row['userTitle']?.toString().trim() ?? '',
          profilePic: row['profilePic']?.toString().trim() ?? '',
        ));
      }
      return out;
    } on DioException {
      return const [];
    }
  }

  /// Digs `canRequestAgainAt` out of the 403 body, which carries it under
  /// `data` (the server puts the payload in the ApiError's data slot).
  static DateTime? _cooldownFrom(dynamic body) {
    dynamic node = body;
    if (node is Map && node['data'] != null) node = node['data'];
    if (node is! Map) return null;
    final raw = node['canRequestAgainAt']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
