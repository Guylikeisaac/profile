import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/api_client_provider.dart';
import '../data/certifications_repository.dart';
import '../data/models/certification.dart';

final certificationsRepositoryProvider = Provider<CertificationsRepository>(
  (ref) => CertificationsRepository(ref.watch(apiClientProvider)),
);

/// The signed-in user's certifications, including PENDING and REJECTED rows.
///
/// Not auto-disposed on purpose: the section sits on the profile screen and
/// the add/edit sheets are pushed over it, so an autoDispose family would tear
/// the list down and re-fetch every time a sheet opens.
final myCertificationsProvider = FutureProvider<List<Certification>>(
  (ref) => ref.watch(certificationsRepositoryProvider).getMine(),
);

/// Another user's VERIFIED certifications.
///
/// Keyed by the **internal auth UUID** (`UserProfile.id`) — this endpoint does
/// not resolve a public handle, so passing one returns an empty list rather
/// than that person's certifications.
final publicCertificationsProvider =
    FutureProvider.autoDispose.family<List<PublicCertification>, String>(
  (ref, userUuid) =>
      ref.watch(certificationsRepositoryProvider).getPublic(userUuid),
);
