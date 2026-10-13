import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/helpers/share_message_builder.dart';
import '../../../core/router/profile_navigation.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../shared/widgets/app_button.dart';
import 'profile_surface.dart';
import '../../home/data/models/home_models.dart';
import '../../home/widgets/feed_post_card.dart';
import '../../post/widgets/post_comments_sheet.dart';
import '../../post/widgets/post_owner_actions.dart';
import '../providers/profile_posts_provider.dart';

/// The profile's **Posts** tab: the profile owner's authored posts, from
/// `GET /post/get-all/{userId}`.
///
/// Renders the same [FeedPostCard] Home and Saved Items use, so a post looks
/// and behaves identically wherever it appears — media, video playback,
/// reactions, comments, save and the overflow menu all come from that one
/// widget rather than a profile-specific copy.
///
/// The overflow menu is deliberately NOT overridden here: [FeedPostCard]
/// derives its rows from author identity, so the owner sees their own set and
/// a visitor sees Report/Block. Passing a fixed list — as Saved Items does —
/// would offer a visitor actions meant for an owner.
class ProfilePostsList extends ConsumerWidget {
  const ProfilePostsList({
    super.key,
    required this.userUuid,
    required this.emptyLabel,
  });

  /// The profile owner's internal auth UUID. The endpoint matches this against
  /// `Post.authorId` and against `req.user.id` to decide ownership — a public
  /// handle returns an empty page.
  final String userUuid;

  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokensOrDefault;
    final feedKey = profilePostsFeedKey(userUuid);
    final state = ref.watch(profilePostsProvider(feedKey));
    final notifier = ref.read(profilePostsProvider(feedKey).notifier);

    Future<void> runAction(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) context.showErrorSnackBar(e.toString());
      }
    }

    if (state.isInitialLoading) {
      return const _CenteredSpinner();
    }

    if (state.initialError != null) {
      return _InlineError(
        message: state.initialError!,
        onRetry: notifier.retry,
      );
    }

    if (state.posts.isEmpty) {
      // No client-side filtering happens on this list, so an empty page really
      // is "nothing to show" — the server already removed anything this viewer
      // may not see. There is nothing to page past in search of a visible row.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Text(
          emptyLabel,
          style: TextStyle(fontSize: 13.5, color: tokens.textTertiary),
        ),
      );
    }

    return Column(
      children: [
        for (final post in state.posts)
          FeedPostCard(
            post: post,
            onLike: () => runAction(() => notifier.toggleLike(post.id)),
            onSave: () => runAction(() => notifier.toggleSave(post.id)),
            onComment: () => _openComments(context, ref, post),
            onShare: () => _sharePost(post.id),
            onAuthorTap: post.author.handle.isEmpty
                ? null
                : () => openPublicProfile(
                      context,
                      userId: post.author.handle,
                    ),
            // Offered only on the signed-in author's own posts — the card
            // prunes both rows for a visitor, so a profile you are looking at
            // never shows you Edit or Delete on someone else's post.
            onEdit: () => openPostEditor(context, post),
            onDelete: () => confirmAndDeletePost(
              context,
              delete: () => notifier.deletePost(post.id),
            ),
          ),
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (state.loadMoreError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Text(
                  state.loadMoreError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: tokens.textTertiary),
                ),
                AppButton.text(label: 'Retry', onPressed: notifier.loadMore),
              ],
            ),
          )
        else if (state.hasMore)
          AppButton.text(label: 'Load more', onPressed: notifier.loadMore),
        const SizedBox(height: 4),
      ],
    );
  }

  void _openComments(BuildContext context, WidgetRef ref, FeedPost post) =>
      openProfilePostComments(
          context, ref, profilePostsFeedKey(userUuid), post);
}

/// Opens the shared comment sheet and bumps the count on [key]'s feed, so the
/// card the user was looking at updates without a refetch.
void openProfilePostComments(
  BuildContext context,
  WidgetRef ref,
  ProfilePostsKey key,
  FeedPost post,
) {
  showPostCommentsSheet(
    context,
    post.id,
    initialCount: post.commentsCount,
    commentsEnabled: post.commentsEnabled,
    onCommentAdded: () => ref
        .read(profilePostsProvider(key).notifier)
        .bumpCommentCount(post.id, 1),
  );
}

Future<void> _sharePost(String postId) async {
  if (postId.isEmpty) return;
  await SharePlus.instance.share(
    ShareParams(
      text: ShareMessages.post(ApiConstants.postShareUrl(postId)),
      subject: ShareMessages.postSubject,
    ),
  );
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: tokens.textTertiary),
          ),
          const SizedBox(height: 10),
          AppButton.secondary(
            label: 'Retry',
            onPressed: onRetry,
            expand: false,
            size: AppButtonSize.compact,
          ),
        ],
      ),
    );
  }
}

/// The profile's inline Posts preview: a horizontal carousel of the newest
/// [kProfilePostsPreviewLimit] posts, then a full-width "View all posts →".
///
/// A glance, not a feed. The profile page already scrolls vertically through
/// eight sections, so a second vertical feed nested inside it buries
/// everything below Activity and gives the posts no natural end. Laying the
/// cards out horizontally bounds the section's height to one card and makes
/// "there is more, tap through" the obvious next move — which is what the
/// website's own carousel does.
///
/// It reads its own provider instance ([profilePostsPreviewKey]) so paging on
/// the All Posts screen can't grow this list behind the user's back, and so
/// the preview only ever requests the three rows it can show.
class ProfilePostsPreview extends ConsumerWidget {
  const ProfilePostsPreview({
    super.key,
    required this.userUuid,
    required this.emptyLabel,
    required this.onViewAll,
  });

  /// The profile owner's internal auth UUID — see [ProfilePostsList.userUuid].
  final String userUuid;
  final String emptyLabel;
  final VoidCallback onViewAll;

  /// Card width. Wide enough to read a post and see its media, narrow enough
  /// that the next card peeks in and says "swipe".
  static const double cardWidth = 300;

  /// The carousel's fixed height.
  ///
  /// Every card in a horizontal row has to agree on a height, so this is
  /// picked to be *tight*: a header, a few lines of text and the action row
  /// over a piece of media, and no more. It replaces a 420 budget that a
  /// text-only post could not come close to filling — which is what left a
  /// tall void between the carousel and "View all posts". Anything taller is
  /// clipped inside the card rather than allowed to stretch the section.
  static const double cardHeight = 316;

  /// Gap between cards.
  static const double cardGap = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokensOrDefault;
    final key = profilePostsPreviewKey(userUuid);
    final state = ref.watch(profilePostsProvider(key));
    final notifier = ref.read(profilePostsProvider(key).notifier);

    Future<void> runAction(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) context.showErrorSnackBar(e.toString());
      }
    }

    if (state.isInitialLoading) return const _CenteredSpinner();

    if (state.initialError != null) {
      return _InlineError(
          message: state.initialError!, onRetry: notifier.retry);
    }

    if (state.posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Text(
          emptyLabel,
          style: TextStyle(fontSize: 13.5, color: tokens.textTertiary),
        ),
      );
    }

    // Sliced as well as request-limited: the server may return more than asked
    // for, and the preview's contract is "at most this many".
    final preview = state.posts.take(kProfilePostsPreviewLimit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            // Asymmetric on purpose: the wider trailing inset leaves the next
            // card peeking in, which is what tells the user the row scrolls.
            padding: const EdgeInsets.only(left: 16, right: 40),
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: cardGap),
            itemBuilder: (context, i) {
              final post = preview[i];
              return PreviewPostCard(
                child: FeedPostCard(
                  post: post,
                  onLike: () => runAction(() => notifier.toggleLike(post.id)),
                  onSave: () => runAction(() => notifier.toggleSave(post.id)),
                  onComment: () =>
                      openProfilePostComments(context, ref, key, post),
                  onShare: () => _sharePost(post.id),
                  onAuthorTap: post.author.handle.isEmpty
                      ? null
                      : () => openPublicProfile(
                            context,
                            userId: post.author.handle,
                          ),
                  // Every card in the row has to agree on one height, so this
                  // one fills the tile and puts its actions on the bottom
                  // edge — three cards whose actions line up, instead of three
                  // that each stop wherever their text ran out.
                  fillHeight: true,
                  // The preview carousel renders the same card as the full
                  // list, so the author gets the same two actions here rather
                  // than having to open "View all posts" to edit.
                  onEdit: () => openPostEditor(context, post),
                  onDelete: () => confirmAndDeletePost(
                    context,
                    delete: () => notifier.deletePost(post.id),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        ViewAllButton(label: 'View all posts', onTap: onViewAll),
      ],
    );
  }
}

/// The tile every carousel post sits in.
///
/// The carousel needs this because `FeedPostCard` is built for a vertical
/// feed: it paints the page's own surface and relies on the rules between
/// posts for separation. Side by side with no wrapper, the cards share one
/// background and read as a single wide strip rather than three posts. So the
/// tile supplies what the vertical feed got from its separators — its own
/// rounded surface, a hairline border, and a clip so media respects the
/// corners instead of spilling past them.
class PreviewPostCard extends StatelessWidget {
  const PreviewPostCard({super.key, required this.child});

  final Widget child;

  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    // The section card pane, clipped so media respects the corners. The
    // tile's height is the carousel's, and the card fills it
    // ([FeedPostCard.fillHeight]): content hugs the top, the action row sits
    // on the bottom edge, and a long post is clipped in between. Handing the
    // card an unbounded height instead — which an `OverflowBox` here used to
    // do — is what left a short post's actions stranded mid-tile above a
    // tall void.
    //
    // No bottom inset: the feed card closes on its own separator rule (it is
    // built for a vertical list), and here that rule should land on the
    // tile's edge and read as its rim, not as a second line above it.
    return ProfileSurface(
      width: ProfilePostsPreview.cardWidth,
      radius: radius,
      clip: true,
      padding: const EdgeInsets.only(top: 4),
      child: child,
    );
  }
}

/// "View all … →" under a preview: a centred text link, not a pane.
///
/// Shared by the Posts carousel and the Activities preview so the two reads of
/// "there is more, tap through" are identical — and drawn the way Network's
/// "View all requests" is, so the app says "there is more" one way. It used to
/// be a full-width raised pill, which made the way *out* of the section the
/// heaviest object in it. The target is still a full 48pt row.
class ViewAllButton extends StatelessWidget {
  const ViewAllButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colorScheme.primary;
    return Center(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.controlAll,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: AppSpacing.minTapTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge(ink),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 16, color: ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
