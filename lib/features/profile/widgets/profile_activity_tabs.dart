import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_context_ext.dart';

/// The Posts / Activities tab row.
///
/// Two looks over one behaviour, so the two surfaces stay in step without
/// pretending to be the same thing:
///
///  * the default **underline** tabs sit inside the profile's Activity
///    section, where they are one control among eight stacked sections and a
///    heavier treatment would compete with the section headers;
///  * [ProfileActivityTabs.segmented] is for the full-screen feed, where the
///    tabs are the screen's primary control and need the weight — and the
///    touch target — to match.
class ProfileActivityTabs extends StatelessWidget {
  const ProfileActivityTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  }) : segmented = false;

  /// Pill segmented control: a filled track with the selected tab raised out
  /// of it. Each segment is at least [minTouchTarget] tall.
  const ProfileActivityTabs.segmented({
    super.key,
    required this.selected,
    required this.onSelected,
  }) : segmented = true;

  /// 0 = Posts, 1 = Activities. Posts is the default everywhere.
  final int selected;
  final ValueChanged<int> onSelected;

  final bool segmented;

  static const List<String> labels = ['Posts', 'Activities'];

  /// Apple's and Material's shared floor for a comfortable tap.
  static const double minTouchTarget = 44;

  @override
  Widget build(BuildContext context) {
    return segmented ? _segmented(context) : _underlined(context);
  }

  /// Painted exactly like the app's `AppSegmented` — the recessed
  /// `surfaceInset` track on a `lineSubtle` edge, the selected segment lifted
  /// to `surfaceContainerHigh` behind the interactive line, label weight
  /// carrying the state — but with 44pt segments. `AppSegmented` insets its
  /// segments 4pt inside a 48pt track, which leaves each one a 40pt target;
  /// this is the screen's primary control, so it keeps the full 44.
  Widget _segmented(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        // 4pt inset and the 1pt edge on each side, around 44pt segments.
        height: minTouchTarget + 10,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.tokensOrDefault.surfaceInset,
          borderRadius: AppRadii.controlAll,
          border: Border.all(color: context.tokensOrDefault.lineSubtle),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: _Segment(
                  label: labels[i],
                  selected: selected == i,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _underlined(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 22),
            _ActivityTab(
              label: labels[i],
              active: selected == i,
              onTap: () => onSelected(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final ink = selected ? colors.onSurface : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      // No explicit `label`: the Text below already supplies one, and setting
      // it here too makes a screen reader announce "Posts Posts".
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.durationFor(context, AppMotion.state),
          curve: AppMotion.curveFor(context, AppMotion.stateCurve),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.surfaceContainerHigh : Colors.transparent,
            borderRadius: AppRadii.smallAll,
            border: Border.all(
              color: selected ? tokens.lineInteractive : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.labelMedium(ink).copyWith(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Semantics(
      button: true,
      selected: active,
      // See the note in [_Segment] — the Text is the label.
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? colors.onSurface : tokens.textTertiary,
              ),
            ),
            const SizedBox(height: 6),
            // The underline is the selection mark; `controlInk` keeps it
            // high-contrast in both themes without spending the accent.
            Container(
              height: 2.5,
              width: 28,
              decoration: BoxDecoration(
                color: active ? tokens.controlInk : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
