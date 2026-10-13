import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/api_client_provider.dart';
import '../data/models/profile_reference.dart';
import '../data/references_repository.dart';

final referencesRepositoryProvider = Provider<ReferencesRepository>(
  (ref) => ReferencesRepository(ref.watch(apiClientProvider)),
);

/// Every reference the signed-in user owns, in every status.
final myReferencesProvider = FutureProvider<List<ProfileReference>>(
  (ref) => ref.watch(referencesRepositoryProvider).getMine(),
);

/// Requests waiting on the signed-in user to write or decline.
///
/// Pull-based by design: reference requests are surfaced to the website
/// through its own Next.js notifications route, which the gateway aggregator
/// the app reads does **not** include. So nothing pushes here — the inbox is
/// refreshed when the profile is opened or pulled down.
final incomingReferenceRequestsProvider =
    FutureProvider<List<IncomingReferenceRequest>>(
  (ref) => ref.watch(referencesRepositoryProvider).getIncoming(),
);

/// Approved references on another profile. Accepts a handle or a UUID.
final publicReferencesProvider =
    FutureProvider.autoDispose.family<List<PublicProfileReference>, String>(
  (ref, userIdOrHandle) =>
      ref.watch(referencesRepositoryProvider).getPublic(userIdOrHandle),
);

/// Re-reads both owner-side reference lists after a mutation.
///
/// They always refresh together because one action can change both: declining
/// an incoming request drops it from the inbox *and* moves the requester's row
/// to REJECTED, and providing a reference publishes into the owner list.
void invalidateOwnerReferencesFrom(WidgetRef ref) {
  ref.invalidate(myReferencesProvider);
  ref.invalidate(incomingReferenceRequestsProvider);
}
