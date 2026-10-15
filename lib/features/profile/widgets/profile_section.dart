import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_motion.dart';
import 'profile_motion.dart';
import 'profile_surface.dart';

/// Marks a subtree whose [ProfileSectionCard]s fold: each shows its header
/// and its first items, and reveals the rest from a "Show N more" line under
/// them (or a tap on the header). Without this ancestor (Edit Profile)
/// sections are always open.
class ProfileFoldingSections extends InheritedWidget {
  const ProfileFoldingSections({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ProfileFoldingSections>() != null;

  @override
  bool updateShouldNotify(ProfileFoldingSections oldWidget) => false;
}

/// Puts a [ProfileFoldMark] after the first [visible] of [items], so a
/// folding section shows exactly those until it is opened. With no more than
/// [visible] items nothing folds.
List<Widget> withFoldMark(List<Widget> items, {int visible = 1}) {
  if (items.length <= visible) return items;
  return [
    ...items.take(visible),
    ProfileFoldMark(hidden: items.length - visible),
    ...items.skip(visible),
  ];
}

/// Where a folding section closes: everything above this mark stays visible,
/// everything below appears when the section opens. Reports its position and
/// how many items it hides to the enclosing section. Paints nothing.
class ProfileFoldMark extends StatefulWidget {
  const ProfileFoldMark({super.key, required this.hidden});

  /// How many items sit below the mark.
  final int hidden;

  @override
  State<ProfileFoldMark> createState() => _ProfileFoldMarkState();
}

class _ProfileFoldMarkState extends State<ProfileFoldMark> {
  @override
  void dispose() {
    _fold?.unmark();
    super.dispose();
  }

  _Fold? _fold;

  void _measure() {
    if (!mounted) return;
    final self = context.findRenderObject();
    final box = context.findAncestorRenderObjectOfType<_RenderCollapseBox>();
    if (self is! RenderBox || box == null || !self.hasSize) return;
    final y = self.localToGlobal(Offset.zero, ancestor: box).dy;
    _fold?.mark(y, widget.hidden);
  }

  @override
  Widget build(BuildContext context) {
    _fold = _FoldScope.maybeOf(context);
    if (_fold != null) {
      // Measured after layout, every time this section lays out again.
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
    return const SizedBox(width: double.infinity, height: 0);
  }
}

/// Open/closed state of one folding section, shared by its card, header and
/// fold mark.
class _Fold extends ChangeNotifier {
  bool open = false;

  /// The mark's offset from the top of the section content, once measured.
  double? markY;

  /// How many items the fold hides.
  int hidden = 0;

  /// A section with nothing below its first item has nothing to open.
  bool get expandable => markY != null && hidden > 0;

  void mark(double y, int count) {
    if (markY != null && (markY! - y).abs() < 0.5 && hidden == count) return;
    markY = y;
    hidden = count;
    notifyListeners();
  }

  void unmark() {
    if (markY == null) return;
    markY = null;
    hidden = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  void toggle() {
    open = !open;
    notifyListeners();
  }
}

class _FoldScope extends InheritedNotifier<_Fold> {
  const _FoldScope({required _Fold fold, required super.child})
      : super(notifier: fold);

  static _Fold? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FoldScope>()?.notifier;
}

/// One profile section: an editorial block on the black page — no pane, just
/// a hairline across the top and generous vertical rhythm.
///
/// Every section — Social Links, Resume, Bio, Experience, Education, Skills,
/// Languages, Proof of Work, References, Certifications — sits in this, so the
/// profile reads as one continuous document rather than a stack of boxes.
/// Inside [ProfileFoldingSections] it folds down to its header.
class ProfileSectionCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const ProfileSectionCard({
    super.key,
    required this.child,
    this.padding,
  });

  /// The block's outer inset. Shared with the rows that sit between sections
  /// (the mutual-connections proof, activity rows) so the column keeps one
  /// rhythm.
  static const EdgeInsets margin = EdgeInsets.fromLTRB(4, 0, 4, 0);
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(16, 22, 16, 30);

  /// A section header's height.
  static const double headerHeight = 44;

  @override
  State<ProfileSectionCard> createState() => _ProfileSectionCardState();
}

class _ProfileSectionCardState extends State<ProfileSectionCard>
    with SingleTickerProviderStateMixin {
  final _Fold _fold = _Fold();

  /// Keeps the fold box (and so the whole section's content) the same element
  /// while the fade layer around it comes and goes.
  final GlobalKey _boxKey = GlobalKey();
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 360),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutQuart,
    reverseCurve: Curves.easeInOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _fold.addListener(_sync);
  }

  void _sync() {
    if (!mounted) return;
    setState(() {});
    if (AppMotion.reducedMotion(context)) {
      _c.value = _fold.open ? 1 : 0;
    } else if (_fold.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _fold.dispose();
    _c.dispose();
    super.dispose();
  }

  /// The folded view: everything down to the fold mark, then a plain
  /// "Show N more" line. Opening grows the box to full height while the hidden
  /// items fade in beneath.
  Widget _folded(BuildContext context, Widget child) {
    final markY = _fold.markY;
    // The box is always present — the fold mark measures itself against it —
    // and simply shows everything until there is something to fold.
    if (!_fold.expandable || markY == null) {
      return _CollapseBox(
          key: _boxKey, factor: 1, collapsedHeight: 0, child: child);
    }
    final factor = _t.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) {
            final edge = (markY / r.height).clamp(0.0, 1.0);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, edge, edge, 1],
              colors: [
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: factor),
                Colors.white.withValues(alpha: factor),
              ],
            ).createShader(r);
          },
          child: _CollapseBox(
            key: _boxKey,
            factor: factor,
            collapsedHeight: markY,
            child: child,
          ),
        ),
        _ShowMore(
          open: _fold.open,
          hidden: _fold.hidden,
          onTap: () {
            HapticFeedback.selectionClick();
            _fold.toggle();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final folding = ProfileFoldingSections.of(context);
    Widget body = widget.child;
    if (folding) {
      body = _FoldScope(
        fold: _fold,
        child: AnimatedBuilder(
          animation: _t,
          child: body,
          builder: (context, child) => _folded(context, child!),
        ),
      );
    }
    return Padding(
      padding: ProfileSectionCard.margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          ProfileDrawnLine(
            color: context.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          Padding(
            padding: widget.padding ?? ProfileSectionCard.contentPadding,
            child: body,
          ),
        ],
      ),
    );
  }
}

/// Shows the top [collapsedHeight] of its child at [factor] 0 and all of it at
/// 1, clipping the rest — a fold that needs no knowledge of the content.
class _CollapseBox extends SingleChildRenderObjectWidget {
  const _CollapseBox({
    super.key,
    required this.factor,
    required this.collapsedHeight,
    super.child,
  });

  final double factor;
  final double collapsedHeight;

  @override
  _RenderCollapseBox createRenderObject(BuildContext context) =>
      _RenderCollapseBox(factor, collapsedHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderCollapseBox render) {
    render
      ..factor = factor
      ..collapsedHeight = collapsedHeight;
  }
}

class _RenderCollapseBox extends RenderProxyBox {
  _RenderCollapseBox(this._factor, this._collapsedHeight);

  double _factor;
  set factor(double v) {
    if (v == _factor) return;
    _factor = v;
    markNeedsLayout();
  }

  double _collapsedHeight;
  set collapsedHeight(double v) {
    if (v == _collapsedHeight) return;
    _collapsedHeight = v;
    markNeedsLayout();
  }

  bool _clipped = false;

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
        parentUsesSize: true);
    final full = c.size.height;
    final closed = math.min(_collapsedHeight, full);
    final h = closed + (full - closed) * _factor.clamp(0.0, 1.0);
    _clipped = h < full - 0.5;
    size = constraints.constrain(Size(c.size.width, h));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (!_clipped) {
      super.paint(context, offset);
      return;
    }
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: layer as ClipRectLayer?,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_clipped && !(Offset.zero & size).contains(position)) return false;
    return super.hitTestChildren(result, position: position);
  }
}

/// The heading of one profile section: a glyph tile, the title, and at most
/// one trailing action.
///
/// ## One treatment, every section
///
/// Each section used to pick its own hue for the tile — amber for Experience,
/// purple for Education, pink for Proof of Work, cyan for Certifications,
/// violet for References, red for Bio — and the add/edit glyphs were brand
/// indigo. Eight stacked sections then read as a legend for a key that does
/// not exist: the colour said nothing, but every tile competed with the
/// heading beside it and with the actual actions on the page.
///
/// A section is structure, not status. The tile is one tonal step off the
/// card with no rim of its own ([ProfileGlyphTile]) carrying `iconInk`
/// (secondary ink), the title is the high-emphasis text, and the action glyph
/// is `controlInk` on a glass disc — so on a dark page the eye lands on the
/// heading first, then the control, and the tile merely labels. Sections stay
/// distinguishable by their glyph shape and their title.
class SectionHeader extends StatelessWidget {
  /// The leading glyph; null for a title-only heading.
  final IconData? icon;

  /// The glyph's colour; null keeps the secondary ink.
  final Color? iconColor;
  final String title;
  final bool showAdd;
  final bool showEdit;

  /// Tap handlers for the trailing add (+) / edit (✎) glyphs. When provided the
  /// glyph becomes an interactive hit target (opens the matching edit sheet);
  /// when null the glyph stays purely presentational.
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  const SectionHeader({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.showAdd = false,
    this.showEdit = false,
    this.onAdd,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fold = _FoldScope.maybeOf(context);
    final row = Row(
      children: [
        if (icon != null) ...[
          ExcludeSemantics(
            child: Icon(icon,
                size: 16, color: iconColor ?? colors.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Semantics(
            header: true,
            label: title,
            excludeSemantics: true,
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: colors.onSurface,
              ),
            ),
          ),
        ),
        if (showAdd)
          SectionHeaderAction(
            icon: Icons.add,
            semanticLabel: 'Add $title',
            onTap: onAdd,
          ),
        if (showEdit)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: SectionHeaderAction(
              icon: Icons.edit_outlined,
              semanticLabel: 'Edit $title',
              onTap: onEdit,
            ),
          ),
      ],
    );
    final header = ConstrainedBox(
      constraints:
          const BoxConstraints(minHeight: ProfileSectionCard.headerHeight),
      child: row,
    );
    if (fold == null || !fold.expandable) return header;
    // The whole heading toggles the section; the add/edit discs keep their
    // own taps.
    return Semantics(
      button: true,
      expanded: fold.open,
      onTapHint: fold.open ? 'Collapse' : 'Expand',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          fold.toggle();
        },
        child: header,
      ),
    );
  }
}

/// The fold control under a folded section: a quiet text line, "Show N more"
/// while closed and "Show less" once open.
class _ShowMore extends StatelessWidget {
  const _ShowMore({
    required this.open,
    required this.hidden,
    required this.onTap,
  });

  final bool open;
  final int hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colorScheme.onSurfaceVariant;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        expanded: open,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                open ? 'Show less' : 'Show $hidden more',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ink,
                  decoration: TextDecoration.underline,
                  decorationColor: ink.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The section header's add / edit control.
///
/// A 32pt glass disc inside a 44pt target, with a high-emphasis glyph: the
/// disc is what says "this is a control" now that the glyph no longer says it
/// with hue, and the press dip is the feedback. The glyph is `controlInk`
/// rather than a dimmed grey on purpose — an add button that looks disabled is
/// worse than one that looks blue.
class SectionHeaderAction extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  const SectionHeaderAction({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ProfileGlassDisc(
      icon: icon,
      semanticLabel: semanticLabel,
      onTap: onTap,
    );
  }
}
