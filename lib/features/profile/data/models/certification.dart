/// Admin verification state of a certification claim.
///
/// The owner sees all three; a *public* viewer never does — the backend's
/// public serializer drops `status`/`rejectionReason` entirely and only ever
/// returns rows that already reached [verified]. See [PublicCertification].
enum CertificationStatus {
  pending,
  verified,
  rejected;

  /// Maps the wire value (`PENDING` · `VERIFIED` · `REJECTED`). An unknown or
  /// missing value degrades to [pending] rather than throwing: a new server
  /// state must not blank the section, and "awaiting review" is the honest
  /// reading of a status this build doesn't recognise (it never claims
  /// verified, and never accuses the user of a rejection).
  static CertificationStatus fromWire(Object? raw) {
    switch (raw?.toString().trim().toUpperCase()) {
      case 'VERIFIED':
        return CertificationStatus.verified;
      case 'REJECTED':
        return CertificationStatus.rejected;
      default:
        return CertificationStatus.pending;
    }
  }

  String get label => switch (this) {
        CertificationStatus.pending => 'In review',
        CertificationStatus.verified => 'Verified',
        CertificationStatus.rejected => 'Rejected',
      };
}

/// A certification as the **owner** sees it (`GET /certifications/me`), which
/// includes the verification state and any reviewer rejection reason.
///
/// The document itself is write-only from the app's point of view: the owner
/// response carries `documentName`/`mimeType` but no readable URL (only the
/// admin-side internal route can sign one), so the UI can say *which* file is
/// attached but cannot re-open it.
class Certification {
  final String id;
  final String name;
  final String? issuingOrganization;
  final DateTime? issueDate;
  final DateTime? expirationDate;
  final String? credentialId;
  final String? credentialUrl;
  final String? documentName;
  final String? mimeType;
  final CertificationStatus status;
  final String? rejectionReason;
  final DateTime? verifiedAt;

  const Certification({
    required this.id,
    required this.name,
    this.issuingOrganization,
    this.issueDate,
    this.expirationDate,
    this.credentialId,
    this.credentialUrl,
    this.documentName,
    this.mimeType,
    this.status = CertificationStatus.pending,
    this.rejectionReason,
    this.verifiedAt,
  });

  /// True when the backend refuses a delete: `DELETE /certifications/{id}`
  /// answers 400 for a VERIFIED row ("Verified certifications cannot be
  /// deleted"), so the UI hides the action instead of offering a call that
  /// will fail.
  bool get isDeletable => status != CertificationStatus.verified;

  /// True when editing will send the row back for review — the backend resets
  /// a VERIFIED or REJECTED row to PENDING on any update, and also whenever a
  /// new document is attached.
  bool get editResetsVerification => status != CertificationStatus.pending;

  bool get hasDocument => (documentName ?? '').trim().isNotEmpty;

  static Certification? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    // A row with no id can't be edited or deleted, and one with no name has
    // nothing to render — either way it's unusable, so drop it rather than
    // showing a blank card the user can't act on.
    if (id.isEmpty || name.isEmpty) return null;
    return Certification(
      id: id,
      name: name,
      issuingOrganization: _text(json['issuingOrganization']),
      issueDate: parseDate(json['issueDate']),
      expirationDate: parseDate(json['expirationDate']),
      credentialId: _text(json['credentialId']),
      credentialUrl: _text(json['credentialUrl']),
      documentName: _text(json['documentName']),
      mimeType: _text(json['mimeType']),
      status: CertificationStatus.fromWire(json['status']),
      rejectionReason: _text(json['rejectionReason']),
      verifiedAt: parseDate(json['verifiedAt']),
    );
  }

  /// Reads the owner list out of `{ data: { certifications: [...] } }`.
  ///
  /// This envelope is NOT the bare-array shape the reference endpoints use —
  /// the certification list is nested one level deeper under `certifications`.
  static List<Certification> listFromResponse(dynamic body) => _rowsOf(body)
      .map(Certification.fromJson)
      .nonNulls
      .toList(growable: false);
}

/// A certification on **someone else's** profile
/// (`GET /certifications/public/{userId}`).
///
/// Deliberately a separate type from [Certification]: the public payload has
/// no `status`, no `rejectionReason` and no document fields, and modelling it
/// as the same class would invite a widget to read owner-only state that is
/// simply absent — or worse, to fall back to a default that leaks a guess
/// about someone's rejected claim. Everything here is verified by definition.
class PublicCertification {
  final String id;
  final String name;
  final String? issuingOrganization;
  final DateTime? issueDate;
  final DateTime? expirationDate;
  final String? credentialId;
  final String? credentialUrl;
  final DateTime? verifiedAt;

  const PublicCertification({
    required this.id,
    required this.name,
    this.issuingOrganization,
    this.issueDate,
    this.expirationDate,
    this.credentialId,
    this.credentialUrl,
    this.verifiedAt,
  });

  static PublicCertification? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    return PublicCertification(
      id: id,
      name: name,
      issuingOrganization: _text(json['issuingOrganization']),
      issueDate: parseDate(json['issueDate']),
      expirationDate: parseDate(json['expirationDate']),
      credentialId: _text(json['credentialId']),
      credentialUrl: _text(json['credentialUrl']),
      verifiedAt: parseDate(json['verifiedAt']),
    );
  }

  static List<PublicCertification> listFromResponse(dynamic body) =>
      _rowsOf(body)
          .map(PublicCertification.fromJson)
          .nonNulls
          .toList(growable: false);
}

/// Unwraps `{data: {certifications: [...]}}`, tolerating a bare `{data: [...]}`
/// or a bare list so a shape tweak degrades to an empty section, not a crash.
List<Map<String, dynamic>> _rowsOf(dynamic body) {
  dynamic node = body;
  if (node is Map && node['data'] != null) node = node['data'];
  if (node is Map && node['certifications'] != null) {
    node = node['certifications'];
  }
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

/// Parses a server date, which arrives as a full ISO timestamp for the audit
/// fields and as a date-only value for `issueDate`/`expirationDate`.
DateTime? parseDate(Object? raw) {
  final value = raw?.toString();
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
