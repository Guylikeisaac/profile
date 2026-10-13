import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_exception.dart';
import '../../../core/providers/api_client_provider.dart';
import '../../post/data/models/post_models.dart' show Activity;
import '../data/activity_repository.dart';

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ApiActivityRepository(ref.watch(apiClientProvider)),
);

/// Page size for the full activity feed.
const int kActivityFeedPageSize = kActivityPageSize;

/// How many activities the profile's inline preview loads and shows.
const int kActivityPreviewLimit = 3;

/// Identifies one activity feed: whose, and at what size.
///
/// The size is part of the key for the same reason the posts feed carries it —
/// the profile preview and the full screen are different surfaces over one
/// endpoint, and a shared key would let the screen's `loadMore` grow the
/// preview behind the user. The preview also requests only the three rows it
/// shows rather than pulling a page and discarding most of it.
typedef ActivityFeedKey = ({String uuid, int limit});

/// The preview's feed for [uuid].
ActivityFeedKey activityPreviewKey(String uuid) =>
    (uuid: uuid, limit: kActivityPreviewLimit);

/// The full "All Activity" feed for [uuid].
ActivityFeedKey activityFullFeedKey(String uuid) =>
    (uuid: uuid, limit: kActivityFeedPageSize);

/// The profile whose activity this is — the internal auth **UUID**
/// (never the public handle).
///
/// This used to carry a type filter as well, because the profile's "Posts" tab
/// was built as `activity?type=POST_CREATED`. That was wrong on two counts:
/// the endpoint returns activity *events*, not posts, and on staging it
/// returns none at all for users whose posts render fine on the website. Posts
/// now come from `/post/get-all/{userId}` via `profilePostsProvider`, and this
/// feed is the Activities tab only — unfiltered, as the website's own
/// `ActivityTabs` renders it.

/// Accumulated paging state for one activity feed, mirroring the house
/// pattern in `AppliedJobsState`: rows loaded so far, the backend's own
/// pagination truth, and initial/load-more status kept separate so pagination
/// failures never discard already-loaded rows.
class ActivityFeedState {
  final List<Activity> activities;

  /// Backend pagination truth from the last successful page.
  final bool hasMore;

  /// The 1-indexed page to request next (`data.pagination.nextPage`);
  /// null when exhausted.
  final int? nextPage;

  /// Total across all pages, kept in sync locally after deletes.
  final int totalActivities;

  /// Ids with a delete/visibility request in flight — their row actions are
  /// disabled so the same row can't stack conflicting mutations.
  final Set<String> pendingIds;

  final bool isInitialLoading;
  final String? initialError;
  final bool isLoadingMore;
  final String? loadMoreError;

  const ActivityFeedState({
    this.activities = const [],
    this.hasMore = false,
    this.nextPage,
    this.totalActivities = 0,
    this.pendingIds = const {},
    this.isInitialLoading = true,
    this.initialError,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  bool get hasActivities => activities.isNotEmpty;

  ActivityFeedState copyWith({
    List<Activity>? activities,
    bool? hasMore,
    int? nextPage,
    bool clearNextPage = false,
    int? totalActivities,
    Set<String>? pendingIds,
    bool? isInitialLoading,
    String? initialError,
    bool clearInitialError = false,
    bool? isLoadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) =>
      ActivityFeedState(
        activities: activities ?? this.activities,
        hasMore: hasMore ?? this.hasMore,
        nextPage: clearNextPage ? null : (nextPage ?? this.nextPage),
        totalActivities: totalActivities ?? this.totalActivities,
        pendingIds: pendingIds ?? this.pendingIds,
        isInitialLoading: isInitialLoading ?? this.isInitialLoading,
        initialError:
            clearInitialError ? null : (initialError ?? this.initialError),
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        loadMoreError:
            clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

/// Paginated activity feed for one profile.
///
/// Ordering is the backend's own reverse-chronological order — pages are
/// appended as received, never re-sorted client-side. Appends are de-duped by
/// activity id, concurrent load-mores are guarded, and a generation counter
/// drops stale responses (a refresh supersedes an in-flight page; a different
/// profile is a different family instance by construction).
///
/// Owner mutations (delete / visibility) are optimistic with rollback on
/// failure; they live here — not in widgets — so a mid-flight navigation
/// can't strand a half-applied change.
class ActivityFeedNotifier extends Notifier<ActivityFeedState> {
  ActivityFeedNotifier(this.key);

  final ActivityFeedKey key;

  /// The profile owner's internal auth UUID.
  String get userUuid => key.uuid;

  /// Rows per request — 3 for the preview, [kActivityFeedPageSize] for the
  /// full feed.
  int get _pageSize => key.limit;

  int _gen = 0;
  int _serverTotal = 0;
  int _localTotalDelta = 0;

  ActivityRepository get _repo => ref.read(activityRepositoryProvider);

  @override
  ActivityFeedState build() {
    _serverTotal = 0;
    _localTotalDelta = 0;
    unawaited(_fetchFirstPage(++_gen));
    return const ActivityFeedState();
  }

  /// Initial-load retry (also used by pull-to-refresh via invalidate).
  Future<void> retry() {
    final gen = ++_gen;
    _serverTotal = 0;
    _localTotalDelta = 0;
    state = const ActivityFeedState();
    return _fetchFirstPage(gen);
  }

  Future<void> _fetchFirstPage(int gen) async {
    try {
      final page = await _repo.loadUserActivities(
        userUuid: userUuid,
        page: 1, // verified contract: pages are 1-indexed
        limit: _pageSize,
      );
      if (!ref.mounted || gen != _gen) return;
      _serverTotal = page.pagination.totalActivities;
      state = ActivityFeedState(
        activities: _dedupe(const [], page.activities),
        hasMore: page.pagination.hasMore,
        nextPage: page.pagination.nextPage,
        totalActivities: _effectiveTotal(),
        isInitialLoading: false,
      );
    } catch (e) {
      if (!ref.mounted || gen != _gen) return;
      state = ActivityFeedState(
        isInitialLoading: false,
        initialError: _messageFor(e),
      );
    }
  }

  /// Fetch and append the next page. No-ops while another load is running or
  /// when the backend says there's nothing more.
  Future<void> loadMore() async {
    final s = state;
    final nextPage = s.nextPage;
    if (s.isInitialLoading ||
        s.isLoadingMore ||
        !s.hasMore ||
        nextPage == null) {
      return;
    }
    final gen = _gen;
    state = s.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    try {
      final page = await _repo.loadUserActivities(
        userUuid: userUuid,
        page: nextPage,
        limit: _pageSize,
      );
      if (!ref.mounted || gen != _gen) return;
      _serverTotal = page.pagination.totalActivities;
      state = state.copyWith(
        activities: _dedupe(state.activities, page.activities),
        hasMore: page.pagination.hasMore,
        nextPage: page.pagination.nextPage,
        clearNextPage: page.pagination.nextPage == null,
        totalActivities: _effectiveTotal(),
        isLoadingMore: false,
      );
    } catch (e) {
      if (!ref.mounted || gen != _gen) return;
      // Already-loaded rows stay visible; the footer offers an inline retry.
      state =
          state.copyWith(isLoadingMore: false, loadMoreError: _messageFor(e));
    }
  }

  /// Deletes [activityId] (own activities only). Optimistically removes ONLY
  /// that row (remembering its position); on failure it is re-inserted where
  /// it was — rows appended by a concurrent loadMore and other rows' changes
  /// are never touched. Returns the user-facing error message, or null on
  /// success. No-ops while the row already has a mutation in flight.
  Future<String?> deleteActivity(String activityId) async {
    if (state.pendingIds.contains(activityId)) return null;
    final index = state.activities.indexWhere((a) => a.id == activityId);
    if (index < 0) return null;
    final removed = state.activities[index];

    _localTotalDelta -= 1;
    state = state.copyWith(
      activities: [
        for (final a in state.activities)
          if (a.id != activityId) a,
      ],
      totalActivities: _effectiveTotal(),
      pendingIds: {...state.pendingIds, activityId},
    );
    try {
      await _repo.deleteActivity(activityId);
      if (ref.mounted) _clearPending(activityId);
      return null;
    } catch (e) {
      if (ref.mounted) {
        // Targeted rollback: put the one row back near where it was; the
        // rest of the (possibly newer) state stays as-is.
        _localTotalDelta += 1;
        final rows = [...state.activities];
        if (!rows.any((a) => a.id == activityId)) {
          rows.insert(index.clamp(0, rows.length), removed);
        }
        state = state.copyWith(
          activities: rows,
          totalActivities: _effectiveTotal(),
        );
        _clearPending(activityId);
      }
      return _messageFor(e);
    }
  }

  /// Sets [activityId]'s visibility to `PUBLIC`/`PRIVATE` (own activities
  /// only). Optimistically patches ONLY that row, adopts the server's
  /// returned activity on success, and on failure restores just that row's
  /// previous visibility — concurrent pagination and other rows' successful
  /// mutations survive. Returns the user-facing error message, or null on
  /// success. No-ops while the row already has a mutation in flight.
  Future<String?> setVisibility(String activityId, String visibility) async {
    if (state.pendingIds.contains(activityId)) return null;
    final index = state.activities.indexWhere((a) => a.id == activityId);
    if (index < 0) return null;
    final previousVisibility = state.activities[index].visibility;

    state = state.copyWith(
      activities: _patchRow(state.activities, activityId,
          (a) => a.copyWithVisibility(visibility)),
      pendingIds: {...state.pendingIds, activityId},
    );
    try {
      final updated = await _repo.setActivityVisibility(
        activityId: activityId,
        visibility: visibility,
      );
      if (ref.mounted) {
        if (updated.id.isNotEmpty) {
          state = state.copyWith(
              activities:
                  _patchRow(state.activities, activityId, (_) => updated));
        }
        _clearPending(activityId);
      }
      return null;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          activities: _patchRow(state.activities, activityId,
              (a) => a.copyWithVisibility(previousVisibility)),
        );
        _clearPending(activityId);
      }
      return _messageFor(e);
    }
  }

  /// Replaces the [id] row via [patch], leaving every other row untouched.
  static List<Activity> _patchRow(
    List<Activity> rows,
    String id,
    Activity Function(Activity) patch,
  ) =>
      [
        for (final a in rows)
          if (a.id == id) patch(a) else a,
      ];

  void _clearPending(String activityId) {
    state = state.copyWith(
      pendingIds: {
        for (final id in state.pendingIds)
          if (id != activityId) id,
      },
    );
  }

  int _effectiveTotal() {
    final adjusted = _serverTotal + _localTotalDelta;
    return adjusted > 0 ? adjusted : 0;
  }

  static List<Activity> _dedupe(
    List<Activity> existing,
    List<Activity> incoming,
  ) {
    final seen = {for (final a in existing) a.id};
    return [
      ...existing,
      for (final a in incoming)
        if (a.id.isEmpty || seen.add(a.id)) a,
    ];
  }

  static String _messageFor(Object e) =>
      e is RepositoryException ? e.message : "We couldn't load this activity.";
}

/// One profile's Activities tab, keyed by the owner's internal auth **UUID**.
final activityFeedProvider = NotifierProvider.autoDispose
    .family<ActivityFeedNotifier, ActivityFeedState, ActivityFeedKey>(
  ActivityFeedNotifier.new,
);
