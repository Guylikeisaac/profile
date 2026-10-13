import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../providers/activity_provider.dart';
import '../providers/profile_posts_provider.dart';
import '../widgets/profile_activity_tabs.dart';
import '../widgets/profile_posts_list.dart';
import '../widgets/profile_view_sections.dart';

/// Everything one profile has posted, reached from the profile's Posts and
/// Activities previews.
///
/// The profile section is a three-item glance; this is the feed. Same two
/// tabs, same two endpoints, same two providers — Posts on
/// `/post/get-all/{uuid}`, Activities on `/activity/user/{uuid}` — but at full
/// page size and paginated, which is why it needs its own screen rather than
/// growing inside the profile's own scroll.
///
/// Chrome follows the Home feed rather than inventing its own: the page paints
/// `colorScheme.surface` end to end, and the single rule below the tab control
/// is the same hairline the feed already draws between posts. Title, tabs and
/// feed therefore read as one column instead of a black bar with a list bolted
/// underneath — the post rhythm below it is `FeedPostCard`'s own, unchanged
/// from Home.
///
/// Works for the signed-in owner and for a visitor: the endpoints resolve the
/// viewer from the bearer token and filter what they return, so nothing here
/// decides visibility.
class ProfileAllPostsScreen extends ConsumerStatefulWidget {
  const ProfileAllPostsScreen({
    super.key,
    required this.userUuid,
    this.isOwner = false,
    this.initialTab = 0,
  });

  /// The profile owner's internal auth **UUID**. Both endpoints key on it; a
  /// public handle returns nothing, so callers must resolve it (the profile
  /// screen already holds it as `UserProfile.id`).
  final String userUuid;

  /// Enables the owner-only activity controls. Never inferred from the uuid —
  /// the caller already knows which profile it opened.
  final bool isOwner;

  /// 0 = Posts, 1 = Activities. Set so "View all activity" lands on the tab
  /// the user asked for; both tabs stay reachable either way.
  final int initialTab;

  @override
  ConsumerState<ProfileAllPostsScreen> createState() =>
      _ProfileAllPostsScreenState();
}

class _ProfileAllPostsScreenState extends ConsumerState<ProfileAllPostsScreen> {
  late int _tab = widget.initialTab;

  bool get _isPosts => _tab == 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final uuid = widget.userUuid.trim();

    return Scaffold(
      // The Home shell's own page colour, so the header, tabs and feed share
      // one ground instead of the three-tone stack this screen used to show.
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(title: _isPosts ? 'All Posts' : 'All Activity'),
            // The tabs sit directly under the title with no rule between
            // them: they belong to the header, and a line there would cut the
            // screen into a bar plus a list — the exact separation this is
            // meant to remove. One rule, below the control, is where the
            // hierarchy actually changes.
            ProfileActivityTabs.segmented(
              selected: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
            _Rule(color: tokens.lineSubtle),
            Expanded(
              child: uuid.isEmpty
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: () async {
                        // Each tab owns its own provider; refreshing the one on
                        // screen must not disturb the other's paging.
                        if (_isPosts) {
                          ref.invalidate(
                            profilePostsProvider(profilePostsFeedKey(uuid)),
                          );
                        } else {
                          ref.invalidate(
                            activityFeedProvider(activityFullFeedKey(uuid)),
                          );
                        }
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        child: _isPosts
                            ? ProfilePostsList(
                                key: ValueKey('all-posts-$uuid'),
                                userUuid: uuid,
                                emptyLabel: 'No posts yet.',
                              )
                            : ProfileActivityFeedList(
                                key: ValueKey('all-activities-$uuid'),
                                userUuid: uuid,
                                isOwner: widget.isOwner,
                                emptyLabel: 'No recent activity yet.',
                              ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact back + title row.
///
/// Deliberately not `AppPageHeader`: that bar is sized for a settings-style
/// destination and its height and inset read as a detached black slab above a
/// feed. This one is the height of a single row and sits on the page colour.
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 2),
      child: Row(
        children: [
          // A 44pt target, but only 22pt of glyph — the back control should be
          // easy to hit without reading as a heavy chrome element.
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, size: 22),
              color: colors.onSurface,
              tooltip: 'Back',
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The same full-bleed hairline the Home feed puts between posts.
class _Rule extends StatelessWidget {
  const _Rule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: color);
}
