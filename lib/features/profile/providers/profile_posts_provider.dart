import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_manager.dart';
import '../../../core/data/repository_exception.dart';
import '../../home/data/models/home_models.dart';
import '../../home/providers/feed_provider.dart';
import '../../post/data/models/post_models.dart' as api;
import '../../post/data/post_repository.dart';
import '../../post/providers/post_created_refresh.dart';
import '../../post/providers/post_providers.dart';

/// Page size for the full-screen posts feed. The endpoint's own default is 10.
const int kProfilePostsPageSize = 10;

/// How many posts the profile's inline preview carousel loads and shows.
///
/// The preview is a glance, not a feed — it must never pull a whole page it
/// won't render, so this is both the request `limit` and the display cap.
const int kProfilePostsPreviewLimit = 3;

/// Identifies one posts feed: whose, and at what size.
///
/// The size is part of the key on purpose. The profile preview and the "All
/// Posts" screen read the same endpoint but are different surfaces with
/// different lifetimes — one shows three cards and never pages, the other
/// paginates. Keying only by uuid would make the screen's `loadMore` grow the
/// preview's list behind it, and a refresh on either would re-fetch at the
/// wrong size. A record, so structurally-equal keys share one instance.
typedef ProfilePostsKey = ({String uuid, int limit});

/// The preview carousel's feed for [uuid].
ProfilePostsKey profilePostsPreviewKey(String uuid) =>
    (uuid: uuid, limit: kProfilePostsPreviewLimit);

/// The full "All Posts" feed for [uuid].
ProfilePostsKey profilePostsFeedKey(String uuid) =>
    (uuid: uuid, limit: kProfilePostsPageSize);

/// Paging state for one profile's authored posts.
///
/// Same shape as `ActivityFeedState` on purpose — the two tabs behave
/// identically from the user's side — but a **separate type**, because the two
/// tabs read different endpoints with different payloads and pagination. A
/// shared state object would be the easiest way to leak one tab's rows,
/// spinner or error into the other.
class ProfilePostsState {
  final List<FeedPost> posts;
  final bool hasMore;

  /// The 1-indexed page to request next; null when exhausted.
  final int? nextPage;

  final bool isInitialLoading;
  final String? initialError;
  final bool isLoadingMore;
  final String? loadMoreError;

  const ProfilePostsState({
    this.posts = const [],
    this.hasMore = false,
    this.nextPage,
    this.isInitialLoading = true,
    this.initialError,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  ProfilePostsState copyWith({
    List<FeedPost>? posts,
    bool? hasMore,
    int? nextPage,
    bool clearNextPage = false,
    bool? isInitialLoading,
    String? initialError,
    bool clearInitialError = false,
    bool? isLoadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) =>
      ProfilePostsState(
        posts: posts ?? this.posts,
        hasMore: hasMore ?? this.hasMore,
        nextPage: clearNextPage ? null : (nextPage ?? this.nextPage),
        isInitialLoading: isInitialLoading ?? this.isInitialLoading,
        initialError:
            clearInitialError ? null : (initialError ?? this.initialError),
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        loadMoreError:
            clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

/// The signed-in user's or another user's authored posts, for the profile's
/// **Posts** tab (`GET /post/get-all/{userId}`).
///
/// This is the tab's own data path, deliberately not the Home feed's: the Home
/// feed is a different query with different pagination and its own bookmark
/// seeding, and loading a profile must never disturb it. Rows are mapped into
/// the shared [FeedPost] model so the profile renders the *same* card as Home
/// and Saved Items, with the same reaction / comment / save behaviour.
///
/// Ordering is the server's (`createdAt` desc) and is never re-sorted here;
/// pages are appended and de-duped by post id.
///
/// Visibility is entirely server-side. A visitor's page already excludes posts
/// they may not see, so nothing is filtered locally — doing so would hide
/// posts the backend deliberately served.
class ProfilePostsNotifier extends Notifier<ProfilePostsState> {
  ProfilePostsNotifier(this.key);

  final ProfilePostsKey key;

  /// The profile owner's internal auth UUID.
  String get userUuid => key.uuid;

  /// Rows per request — 3 for the preview, [kProfilePostsPageSize] for the
  /// full feed.
  int get _pageSize => key.limit;

  int _gen = 0;

  /// The viewer's bookmarked post ids, read once per build so every page can
  /// seed `savedByMe` — the per-user endpoint doesn't carry bookmark state.
  Set<String> _bookmarked = const {};

  PostRepository get _repo => ref.read(postRepositoryProvider);

  @override
  ProfilePostsState build() {
    _bookmarked = const {};
    if (userUuid.trim().isEmpty) {
      // Nothing to query — a profile payload can arrive without `id`. Return
      // the settled empty state rather than letting `_fetchFirstPage` assign
      // it: a synchronous assignment made *during* build is overwritten by
      // build's own return value, leaving the tab spinning forever.
      return const ProfilePostsState(isInitialLoading: false);
    }
    unawaited(_fetchFirstPage(++_gen));
    return const ProfilePostsState();
  }

  /// Initial-load retry, also used by pull-to-refresh.
  Future<void> retry() {
    final gen = ++_gen;
    state = const ProfilePostsState();
    return _fetchFirstPage(gen);
  }

  Future<void> _fetchFirstPage(int gen) async {
    // Only reachable with an empty uuid via [retry], which has already reset
    // state to "loading"; build() short-circuits before ever calling this.
    if (userUuid.trim().isEmpty) {
      state = const ProfilePostsState(isInitialLoading: false);
      return;
    }
    try {
      // Saved-state first so page 1 renders bookmarks correctly, and
      // non-fatally: a bookmark hiccup must not blank someone's posts.
      _bookmarked = await _loadBookmarks();
      final res = await _repo.getUserPosts(
        userId: userUuid,
        page: 1,
        limit: _pageSize,
      );
      if (!ref.mounted || gen != _gen) return;
      state = ProfilePostsState(
        posts: _dedupe(const [], res.posts.map(_map).toList()),
        hasMore: _hasMore(res),
        nextPage: _nextPage(res),
        isInitialLoading: false,
      );
    } catch (e) {
      if (!ref.mounted || gen != _gen) return;
      state = ProfilePostsState(
        isInitialLoading: false,
        initialError: _messageFor(e),
      );
    }
  }

  /// Fetch and append the next page. No-ops while a load is running or when
  /// the server says there is nothing more.
  Future<void> loadMore() async {
    final s = state;
    final next = s.nextPage;
    if (s.isInitialLoading || s.isLoadingMore || !s.hasMore || next == null) {
      return;
    }
    final gen = _gen;
    state = s.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    try {
      final res = await _repo.getUserPosts(
        userId: userUuid,
        page: next,
        limit: _pageSize,
      );
      if (!ref.mounted || gen != _gen) return;
      state = state.copyWith(
        posts: _dedupe(state.posts, res.posts.map(_map).toList()),
        hasMore: _hasMore(res),
        nextPage: _nextPage(res),
        clearNextPage: _nextPage(res) == null,
        isLoadingMore: false,
      );
    } catch (e) {
      if (!ref.mounted || gen != _gen) return;
      // Loaded rows stay on screen; the footer offers an inline retry.
      state = state.copyWith(
        isLoadingMore: false,
        loadMoreError: _messageFor(e),
      );
    }
  }

  // ── Post interactions (same repository as Home and Saved Items) ────────────

  /// Primary Like: add a [kDefaultReactionType] (`LIKE`) when the user hasn't
  /// reacted, else clear theirs.
  Future<void> toggleLike(String postId) {
    final target = _find(postId);
    if (target == null) return Future.value();
    return target.reactedByMe ? removeReaction(postId) : _addLike(postId);
  }

  /// Adds the viewer's Like (`POST /interaction/on/{postId}/LIKE`).
  Future<void> _addLike(String postId) async {
    final before = state.posts;
    final userId = AuthManager().currentUser?.id ?? '';
    if (userId.isEmpty) return;
    final target = _find(postId);
    if (target == null) return;

    const type = kDefaultReactionType;
    final counts = Map<String, int>.from(target.reactionCounts);
    counts[type] = (counts[type] ?? 0) + 1;
    _applyReaction(postId, counts, type);

    try {
      await _repo.addReaction(postId: postId, type: type, userId: userId);
    } catch (_) {
      if (ref.mounted) state = state.copyWith(posts: before);
      rethrow;
    }
  }

  /// Removes the viewer's reaction, whatever its type.
  Future<void> removeReaction(String postId) async {
    final before = state.posts;
    final userId = AuthManager().currentUser?.id ?? '';
    if (userId.isEmpty) return;
    final target = _find(postId);
    if (target == null || target.myReactionType == null) return;

    final counts = Map<String, int>.from(target.reactionCounts);
    final prev = target.myReactionType!;
    // Never below zero, as on the website (`Math.max(... - 1, 0)`): the
    // Like button renders the sum, so a stray -1 would show.
    counts[prev] = math.max((counts[prev] ?? 1) - 1, 0);
    _applyReaction(postId, counts, null);

    try {
      await _repo.removeReaction(postId: postId, userId: userId);
    } catch (_) {
      if (ref.mounted) state = state.copyWith(posts: before);
      rethrow;
    }
  }

  /// Toggles the bookmark, keeping the Home feed's copy of the card in step
  /// without forcing it to refetch.
  Future<void> toggleSave(String postId) async {
    final before = state.posts;
    final target = _find(postId);
    if (target == null) return;
    _patch(postId, (p) => p.copyWith(savedByMe: !p.savedByMe));
    try {
      final saved = await _repo.toggleBookmark(postId);
      if (!ref.mounted) return;
      _patch(postId, (p) => p.copyWith(savedByMe: saved));
      if (saved) {
        _bookmarked = {..._bookmarked, postId};
      } else {
        _bookmarked = {
          for (final id in _bookmarked)
            if (id != postId) id,
        };
      }
      forEachLoadedHomeFeed(
          ref.container, (feed) => feed.setSavedLocally(postId, saved));
    } catch (_) {
      if (ref.mounted) state = state.copyWith(posts: before);
      rethrow;
    }
  }

  /// Bumps a post's comment count locally after the viewer comments.
  void bumpCommentCount(String postId, int added) {
    if (added <= 0) return;
    _patch(postId, (p) => p.copyWith(commentsCount: p.commentsCount + added));
  }

  /// Deletes the signed-in author's own post, then drops it here and from every
  /// other surface that was showing it.
  ///
  /// The row goes **after** the server confirms, so a refusal (403 on someone
  /// else's post, 404 on one already gone) leaves the list as it is and the
  /// caller shows the reason — see `confirmAndDeletePost`.
  Future<void> deletePost(String postId) async {
    final container = ref.container;
    await _repo.deletePost(postId);
    if (ref.mounted) removePostLocally(postId);
    // This notifier is family-keyed and autoDispose, and the hook invalidates
    // the whole family — including the instance the deletion came from, which is
    // why the local removal above happens first (the visible list loses the row
    // immediately rather than after a refetch).
    refreshPostDeletedSurfaces(container, postId: postId);
  }

  /// Drops a post from the loaded pages without a request — for a delete that
  /// happened on another surface.
  void removePostLocally(String postId) {
    state = state.copyWith(posts: [
      for (final p in state.posts)
        if (p.id != postId) p,
    ]);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<Set<String>> _loadBookmarks() async {
    try {
      return await _repo
          .myBookmarkedPostIds(AuthManager().currentUser?.userId ?? '');
    } catch (_) {
      // Non-fatal: posts render un-bookmarked rather than not at all.
      return const {};
    }
  }

  FeedPost _map(api.Post p) =>
      feedPostFromApiPost(p, savedByMe: _bookmarked.contains(p.id));

  /// Trusts the server's pagination block over the row count. The per-user
  /// endpoint filters by visibility *after* paging, so a page shorter than the
  /// limit can still be followed by more pages.
  static bool _hasMore(api.PostResponse res) =>
      res.pagination?.hasNextPage ?? false;

  static int? _nextPage(api.PostResponse res) {
    final p = res.pagination;
    if (p == null || !p.hasNextPage) return null;
    return p.currentPage + 1;
  }

  FeedPost? _find(String postId) {
    for (final p in state.posts) {
      if (p.id == postId) return p;
    }
    return null;
  }

  void _applyReaction(String postId, Map<String, int> counts, String? mine) {
    _patch(
      postId,
      (p) => p.copyWith(
        reactionCounts: counts,
        myReactionType: mine,
        clearMyReaction: mine == null,
      ),
    );
  }

  void _patch(String postId, FeedPost Function(FeedPost) patch) {
    state = state.copyWith(posts: [
      for (final p in state.posts)
        if (p.id == postId) patch(p) else p,
    ]);
  }

  static List<FeedPost> _dedupe(
    List<FeedPost> existing,
    List<FeedPost> incoming,
  ) {
    final seen = {for (final p in existing) p.id};
    return [
      ...existing,
      for (final p in incoming)
        if (p.id.isEmpty || seen.add(p.id)) p,
    ];
  }

  static String _messageFor(Object e) =>
      e is RepositoryException ? e.message : "We couldn't load these posts.";
}

/// One posts feed, keyed by the owner's internal auth **UUID** and its size —
/// see [ProfilePostsKey].
///
/// Family-keyed and autoDispose so each surface pages independently and a
/// closed profile stops holding rows — the same lifetime as
/// `activityFeedProvider`, which the Activities tab uses.
final profilePostsProvider = NotifierProvider.autoDispose
    .family<ProfilePostsNotifier, ProfilePostsState, ProfilePostsKey>(
  ProfilePostsNotifier.new,
);
