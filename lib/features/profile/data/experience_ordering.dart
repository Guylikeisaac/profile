/// The one place that decides "which role is the current one" and "what order
/// do history rows go in" for every profile surface.
///
/// `experience/all` (and the `experience[]` embedded in `work-details`) returns
/// rows in no guaranteed order — on staging it came back with the current role
/// LAST, which is why the profile timeline showed Codeaamy (Dec 2024 – Present)
/// underneath four older internships. Nothing downstream sorted it, so the list
/// was simply whatever the query planner handed back.
///
/// The rule here is deliberately identical to the one onboarding uses when it
/// picks a role to prefill (`OnboardingHydrationService.mostRecentExperience`),
/// so the screen you fill in and the profile you end up with can never disagree.
library;

import 'models/user_profile.dart';

/// Newest-first comparator for experience rows:
///
///   1. a current role always outranks a past one;
///   2. then the later END date — a missing end date means "open ended", which
///      ranks above any closed role;
///   3. then the later START date (this is what separates two current roles);
///   4. then the record id, purely so the order is stable and independent of
///      the order the server happened to return.
int compareExperienceRecency(ProfileEntry a, ProfileEntry b) {
  if (a.currentlyWorking != b.currentlyWorking) {
    return a.currentlyWorking ? -1 : 1;
  }
  final byEnd = _newestFirst(a.endDate, b.endDate);
  if (byEnd != 0) return byEnd;
  final byStart = _newestFirst(a.startDate, b.startDate);
  if (byStart != 0) return byStart;
  return (a.id ?? '').compareTo(b.id ?? '');
}

/// Same ordering for education. Degrees have no "currentlyWorking" flag, so an
/// in-progress course (no end date) sorts to the top, then latest graduation.
int compareEducationRecency(ProfileEntry a, ProfileEntry b) {
  final byEnd = _newestFirst(a.endDate, b.endDate);
  if (byEnd != 0) return byEnd;
  final byStart = _newestFirst(a.startDate, b.startDate);
  if (byStart != 0) return byStart;
  return (a.id ?? '').compareTo(b.id ?? '');
}

List<ProfileEntry> sortExperiencesNewestFirst(List<ProfileEntry> rows) =>
    [...rows]..sort(compareExperienceRecency);

List<ProfileEntry> sortEducationsNewestFirst(List<ProfileEntry> rows) =>
    [...rows]..sort(compareEducationRecency);

/// The row that drives "where do they work now" — the current role if there is
/// one, otherwise the most recently ended one. Null when there is no history.
ProfileEntry? currentOrLatestExperience(List<ProfileEntry> rows) =>
    rows.isEmpty ? null : sortExperiencesNewestFirst(rows).first;

/// The canonical company name for the basic-info/header surfaces.
///
/// `work-details.currentCompany` is a denormalised scalar that drifts: on
/// staging it still read "Xero Apps" minutes after the current role had been
/// saved as Codeaamy, and it changed on its own between two reads of the same
/// session. So the experience rows win whenever there are any — [fallback] is
/// only for an account with no experience history at all (a fresher, or a
/// recruiter who typed a company but never added a role).
///
/// If the winning row has no company name we return empty rather than reaching
/// back for the stale scalar: blank beats wrong.
String canonicalCurrentCompany(
  List<ProfileEntry> experiences, {
  required String fallback,
}) {
  final top = currentOrLatestExperience(experiences);
  if (top == null) return fallback.trim();
  return top.subtitle.trim();
}

/// Descending by date, with `null` treated as "still open" and therefore
/// newest — the same convention the onboarding hydrator uses.
int _newestFirst(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return b.compareTo(a);
}
