/// Lifecycle of a reference row.
///
/// Two flows share this enum, which is why [pending] and [requested] both
/// exist and are not interchangeable:
///
///  * **SyncUp-to-SyncUp** (the only flow this app implements): the owner asks
///    another member → [requested]; the target writes it → [approved] straight
///    away, or declines → [rejected]. It never passes through [pending].
///  * **Legacy external reviewer** (web-only, token link): a stranger submits
///    → [pending], and the owner then approves or rejects. The app doesn't
///    create these, but an account can still hold rows in that state from the
///    website, so they have to render.
///
/// [expired] is set by the server when a request outlives its 30-day token.
enum ReferenceStatus {
  requested,
  pending,
  approved,
  rejected,
  expired,

  /// A state this build doesn't know. Kept explicit rather than folded into
  /// one of the real values so nothing can mistake an unrecognised row for an
  /// approved (i.e. publishable) one.
  unknown;

  static ReferenceStatus fromWire(Object? raw) {
    switch (raw?.toString().trim().toUpperCase()) {
      case 'REQUESTED':
        return ReferenceStatus.requested;
      case 'PENDING':
        return ReferenceStatus.pending;
      case 'APPROVED':
        return ReferenceStatus.approved;
      case 'REJECTED':
        return ReferenceStatus.rejected;
      case 'EXPIRED':
        return ReferenceStatus.expired;
      default:
        return ReferenceStatus.unknown;
    }
  }

  /// Word-for-word the website's `statusLabel` map, so the same row reads the
  /// same on both platforms.
  String get label => switch (this) {
        ReferenceStatus.requested => 'Awaiting response',
        ReferenceStatus.pending => 'Pending approval',
        ReferenceStatus.approved => 'Approved',
        ReferenceStatus.rejected => 'Declined',
        ReferenceStatus.expired => 'Expired',
        ReferenceStatus.unknown => 'Unknown',
      };

  /// Only an approved reference carries a testimonial worth showing.
  bool get isPublished => this == ReferenceStatus.approved;
}

/// The minimal SyncUp identity attached to a reference — used for the reviewer
/// on the owner's list and the requester in the inbox.
class ReferenceUser {
  /// Internal auth UUID.
  final String id;

  /// Public handle, e.g. `nitin-jiwnani-1` — what a profile route wants.
  final String handle;
  final String name;
  final String title;
  final String profilePic;

  const ReferenceUser({
    required this.id,
    required this.handle,
    required this.name,
    this.title = '',
    this.profilePic = '',
  });

  static ReferenceUser? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final name = json['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    return ReferenceUser(
      id: json['id']?.toString() ?? '',
      // `userId` on this payload is the public handle, not the UUID — `id` is
      // the UUID. Getting these the wrong way round sends profile taps to a
      // 404, so the names are deliberately unambiguous on this side.
      handle: json['userId']?.toString() ?? '',
      name: name,
      title: json['userTitle']?.toString().trim() ?? '',
      profilePic: json['profilePic']?.toString().trim() ?? '',
    );
  }
}

/// A reference row as its **owner** sees it (`GET /references/all`).
///
/// Carries the state the owner is entitled to: the status, the reviewer's
/// email where one was recorded, and the cooldown timestamp. None of this may
/// reach a public surface — see [PublicProfileReference].
class ProfileReference {
  final String id;

  /// The reviewer's auth UUID when this is a SyncUp-to-SyncUp reference.
  ///
  /// Kept separately from [reviewer]: the owner serializer nulls
  /// `reviewerProfile` for a **deactivated** reviewer but still returns
  /// `reviewerUserId`, so treating a missing profile as "legacy external
  /// reviewer" would offer a delete the server refuses.
  final String? reviewerUserId;

  final ReferenceUser? reviewer;
  final String reviewerName;

  /// Owner-only. Present for legacy external reviewers; never rendered on
  /// anyone else's profile.
  final String? reviewerEmail;
  final String? reviewerTitle;
  final String? reviewerCompany;
  final String? relationship;
  final String? reviewText;
  final ReferenceStatus status;
  final bool isExpired;

  /// When a declined request may be re-sent (10-day cooldown). Null when the
  /// row isn't in cooldown.
  final DateTime? canRequestAgainAt;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  const ProfileReference({
    required this.id,
    required this.reviewerName,
    this.reviewerUserId,
    this.reviewer,
    this.reviewerEmail,
    this.reviewerTitle,
    this.reviewerCompany,
    this.relationship,
    this.reviewText,
    this.status = ReferenceStatus.unknown,
    this.isExpired = false,
    this.canRequestAgainAt,
    this.approvedAt,
    this.createdAt,
  });

  /// The server refuses to delete a SyncUp-linked row that hasn't resolved:
  /// removing an open or declined request would erase the record the cooldown
  /// is computed from. A legacy row (no linked reviewer) can always go.
  bool get isDeletable => !isSyncUpLinked || status == ReferenceStatus.approved;

  /// "Engineering Manager at SyncUp" — the reviewer's own attribution, joined
  /// exactly as the website joins it. Empty when they gave neither.
  String get contextLine {
    final parts = [reviewerTitle, reviewerCompany]
        .map((e) => e?.trim() ?? '')
        .where((e) => e.isNotEmpty);
    return parts.join(' at ');
  }

  /// True for a SyncUp-to-SyncUp request. The legacy external-reviewer flow
  /// (token link, website-only) leaves this null, and its rows get different
  /// copy — there is nobody on SyncUp to be "waiting for".
  bool get isSyncUpLinked =>
      reviewerUserId != null && reviewerUserId!.isNotEmpty;

  /// The line under the row when there is no testimonial to show yet.
  ///
  /// Mirrors the website's per-status copy, so a pending request reads as one
  /// concrete thing that is happening rather than a generic "waiting" banner.
  /// Returns null when [reviewText] should be shown instead.
  String? statusLine({String Function(DateTime)? formatDate}) {
    if ((reviewText ?? '').trim().isNotEmpty) return null;
    final who = reviewerName.trim().isEmpty ? 'them' : reviewerName.trim();
    switch (status) {
      case ReferenceStatus.requested:
        return isSyncUpLinked
            ? 'Waiting for $who to respond.'
            : 'Share the link with $who to collect their review.';
      case ReferenceStatus.rejected:
        final until = canRequestAgainAt;
        if (until != null && formatDate != null) {
          return 'You can request another reference from $who after '
              '${formatDate(until)}.';
        }
        return 'You can request another reference from $who now.';
      case ReferenceStatus.expired:
        return 'This request went unanswered and expired. You can request again.';
      case ReferenceStatus.pending:
      case ReferenceStatus.approved:
      case ReferenceStatus.unknown:
        return null;
    }
  }

  static ProfileReference? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final reviewer = ReferenceUser.fromJson(json['reviewerProfile']);
    return ProfileReference(
      id: id,
      reviewerUserId: _text(json['reviewerUserId']),
      reviewer: reviewer,
      reviewerName:
          json['reviewerName']?.toString().trim() ?? reviewer?.name ?? '',
      reviewerEmail: _text(json['reviewerEmail']),
      reviewerTitle: _text(json['reviewerTitle']),
      reviewerCompany: _text(json['reviewerCompany']),
      relationship: _text(json['relationship']),
      reviewText: _text(json['reviewText']),
      status: ReferenceStatus.fromWire(json['status']),
      isExpired: json['isExpired'] == true,
      canRequestAgainAt: _date(json['canRequestAgainAt']),
      approvedAt: _date(json['approvedAt']),
      createdAt: _date(json['createdAt']),
    );
  }

  static List<ProfileReference> listFromResponse(dynamic body) => _rowsOf(body)
      .map(ProfileReference.fromJson)
      .nonNulls
      .toList(growable: false);
}

/// An approved reference on **someone else's** profile
/// (`GET /references/public/{userId}`).
///
/// A separate type on purpose. The public serializer drops `status`,
/// `reviewerEmail`, `requestToken` and every timestamp except `approvedAt`;
/// modelling it as [ProfileReference] would give widgets fields that don't
/// exist on this route and make it far too easy to render owner-only data on a
/// visitor's screen.
class PublicProfileReference {
  final String id;
  final ReferenceUser? reviewer;
  final String reviewerName;
  final String? reviewerTitle;
  final String? reviewerCompany;
  final String? relationship;
  final String? reviewText;
  final DateTime? approvedAt;

  const PublicProfileReference({
    required this.id,
    required this.reviewerName,
    this.reviewer,
    this.reviewerTitle,
    this.reviewerCompany,
    this.relationship,
    this.reviewText,
    this.approvedAt,
  });

  String get contextLine {
    final parts = [reviewerTitle, reviewerCompany]
        .map((e) => e?.trim() ?? '')
        .where((e) => e.isNotEmpty);
    return parts.join(' at ');
  }

  static PublicProfileReference? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final reviewer = ReferenceUser.fromJson(json['reviewerProfile']);
    return PublicProfileReference(
      id: id,
      reviewer: reviewer,
      reviewerName:
          json['reviewerName']?.toString().trim() ?? reviewer?.name ?? '',
      reviewerTitle: _text(json['reviewerTitle']),
      reviewerCompany: _text(json['reviewerCompany']),
      relationship: _text(json['relationship']),
      reviewText: _text(json['reviewText']),
      approvedAt: _date(json['approvedAt']),
    );
  }

  static List<PublicProfileReference> listFromResponse(dynamic body) =>
      _rowsOf(body)
          .map(PublicProfileReference.fromJson)
          .nonNulls
          .toList(growable: false);
}

/// A request someone sent TO the signed-in user, awaiting their decision
/// (`GET /references/incoming`). The server only ever returns REQUESTED rows
/// here, so there is no status field to model.
class IncomingReferenceRequest {
  final String id;
  final ReferenceUser? requester;
  final String? relationship;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const IncomingReferenceRequest({
    required this.id,
    this.requester,
    this.relationship,
    this.createdAt,
    this.expiresAt,
  });

  String get requesterName => requester?.name ?? 'A SyncUp member';

  static IncomingReferenceRequest? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return IncomingReferenceRequest(
      id: id,
      requester: ReferenceUser.fromJson(json['requester']),
      relationship: _text(json['relationship']),
      createdAt: _date(json['createdAt']),
      expiresAt: _date(json['tokenExpiresAt']),
    );
  }

  static List<IncomingReferenceRequest> listFromResponse(dynamic body) =>
      _rowsOf(body)
          .map(IncomingReferenceRequest.fromJson)
          .nonNulls
          .toList(growable: false);
}

/// Unwraps `{data: [...]}` — the reference routes return a bare array under
/// `data`, unlike certifications which nest one level deeper.
List<Map<String, dynamic>> _rowsOf(dynamic body) {
  dynamic node = body;
  if (node is Map && node['data'] != null) node = node['data'];
  if (node is! List) return const [];
  return [
    for (final row in node)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

String? _text(Object? raw) {
  final value = raw?.toString().trim();
  return (value == null || value.isEmpty) ? null : value;
}

DateTime? _date(Object? raw) {
  final value = raw?.toString();
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
