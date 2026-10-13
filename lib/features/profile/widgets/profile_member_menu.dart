import 'package:flutter/material.dart';

import 'profile_sheet_kit.dart';

/// What someone can do from the "…" on **another member's** profile.
enum ProfileMemberAction { copyLink, removeConnection, block, report }

/// Keys for the widget tests (`profile_member_menu_test.dart`).
@visibleForTesting
Key profileMemberActionKey(ProfileMemberAction action) =>
    ValueKey('profile-member-action:${action.name}');

/// The other-member overflow sheet. Resolves to the row that was tapped, or
/// null when the sheet was dismissed; the screen owns what each row then does,
/// so nothing here talks to a repository.
///
/// [canRemoveConnection] is true only for an **accepted** connection whose
/// record id is known: `DELETE /connection/:connectionId` takes that id and
/// refuses anything that is not `ACCEPTED` (pending requests have Withdraw and
/// Ignore instead, and those stay on the hero button). The row is left out
/// rather than shown disabled — a greyed "Remove connection" on a stranger's
/// profile reads as a bug, not as information.
///
/// Block and Report are offered in every relationship state, which is the
/// point of the menu existing at all: before it, neither could be reached from
/// a profile.
///
/// Drawn by the profile's shared action sheet, so it is the same glass, the
/// same rows and the same destructive treatment as the owner's own "…".
Future<ProfileMemberAction?> showProfileMemberMenu(
  BuildContext context, {
  required String name,
  required bool canRemoveConnection,
}) {
  final who = name.trim().isEmpty ? 'this member' : name.trim();
  return showProfileActionSheet<ProfileMemberAction>(
    context,
    // Over the home shell's floating nav, like the app's other sheets.
    useRootNavigator: true,
    actions: [
      ProfileSheetAction(
        value: ProfileMemberAction.copyLink,
        key: profileMemberActionKey(ProfileMemberAction.copyLink),
        icon: Icons.link,
        label: 'Copy profile link',
      ),
      if (canRemoveConnection)
        ProfileSheetAction(
          value: ProfileMemberAction.removeConnection,
          key: profileMemberActionKey(ProfileMemberAction.removeConnection),
          icon: Icons.person_remove_outlined,
          label: 'Remove connection',
          destructive: true,
        ),
      ProfileSheetAction(
        value: ProfileMemberAction.block,
        key: profileMemberActionKey(ProfileMemberAction.block),
        icon: Icons.block,
        label: 'Block $who',
        destructive: true,
      ),
      ProfileSheetAction(
        value: ProfileMemberAction.report,
        key: profileMemberActionKey(ProfileMemberAction.report),
        icon: Icons.flag_outlined,
        label: 'Report profile',
        destructive: true,
      ),
    ],
  );
}
