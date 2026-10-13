import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/theme/semantic_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_chip.dart';
import '../../../shared/widgets/app_sheet.dart';
import 'profile_surface.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Profile edit-sheet kit
///
/// The shared building blocks for the eleven profile edit/add bottom sheets
/// (see `SyncUp_Profile_Edit_Screens_Design_Spec.md`). One sheet shell, two
/// height behaviours (content-height lists vs near-full-height forms), three
/// top-bar variants, plus the underline fields / chip groups / accent pickers
/// the forms compose. Concrete sheets live in `profile_edit_sheets.dart`.
///
/// Built on the app's shared kit rather than beside it: every sheet is an
/// `AppSheetFrame` (the `SurfaceSpecs.overlay` pane, the shared handle, the
/// keyboard and system-bar handling), footers and header actions are
/// `AppButton`s, selection chips are `AppChip.filter`. What stays here is the
/// profile-specific furniture — the section-style header, underline fields,
/// accent swatches. No hue is spent on chrome, so a user's chosen accent is the
/// only colour a sheet carries.
/// ─────────────────────────────────────────────────────────────────────────

// Spec tokens -----------------------------------------------------------------

// The former file-level `kSheet*` tokens are gone:
//
//   colors.primary     -> colorScheme.primary
//   colors.surfaceContainerHigh   -> colorScheme.surfaceContainerHigh
//   colors.outline -> colorScheme.outline
//   colors.onSurface      -> colorScheme.onSurface
//   tokens.textTertiary       -> tokens.textTertiary
//   colors.outlineVariant    -> colorScheme.outlineVariant
//   kSheetDim        -> the theme's scrim, via BottomSheetThemeData
//
// `kSaturatedAccents`, `kPastelAccents` and `kCoverGradients` below stay fixed
// — they are **user-chosen content**, not chrome. A cover the user picked must
// look the same whichever appearance they are in.

/// Saturated accent palette — Experience + Skill forms.
///
/// **User-chosen content, fixed in both themes.** An accent the user picked for
/// an experience entry is stored on their profile and shown to visitors; it
/// must look the same whatever appearance either of them is using. The same
/// goes for [kPastelAccents] and [kCoverGradients] below.
///
/// This is why `profile_sheet_kit.dart` stays on
/// `tool/raw_colors_allowlist.txt`.
const List<Color> kSaturatedAccents = [
  Color(0xFF6366F1), // indigo
  Color(0xFF8B5CF6), // purple
  Color(0xFFEC4899), // pink
  Color(0xFF10B981), // emerald
  Color(0xFFF59E0B), // amber
  Color(0xFF3B82F6), // blue
  Color(0xFFEF4444), // red
  Color(0xFF111827), // black
];

/// Pastel accent palette — Education form (intentionally softer per spec).
const List<Color> kPastelAccents = [
  Color(0xFFC7D2FE), // light lavender
  Color(0xFFDDD6FE), // light purple
  Color(0xFFFBCFE8), // light pink
  Color(0xFFBBF7D0), // light mint
  Color(0xFFFDE68A), // light amber
  Color(0xFFBFDBFE), // light blue
  Color(0xFFFECDD3), // light rose
  Color(0xFFE5E7EB), // light gray
];

/// One named cover gradient preset (Edit Cover · Color).
class CoverGradient {
  final String name;
  final List<Color> colors;
  const CoverGradient(this.name, this.colors);
}

const List<CoverGradient> kCoverGradients = [
  CoverGradient('Indigo', [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
  CoverGradient('Ocean', [Color(0xFF0EA5E9), Color(0xFF2563EB)]),
  CoverGradient('Emerald', [Color(0xFF10B981), Color(0xFF059669)]),
  CoverGradient('Sunset', [Color(0xFFF59E0B), Color(0xFFEF4444)]),
  CoverGradient('Rose', [Color(0xFFEC4899), Color(0xFFF43F5E)]),
  CoverGradient('Midnight', [Color(0xFF1E1B4B), Color(0xFF312E81)]),
  CoverGradient('Teal', [Color(0xFF14B8A6), Color(0xFF0EA5E9)]),
  CoverGradient('Peach', [Color(0xFFFB923C), Color(0xFFF97316)]),
  CoverGradient('Dark', [Color(0xFF111827), Color(0xFF0B061B)]),
];

// Sheet presentation ----------------------------------------------------------

/// Presents [builder]'s content in the app's shared sheet frame
/// ([AppSheetFrame]): the overlay glass pane, the drag handle, lifted above
/// the keyboard and kept clear of the system bar. [fullHeight] rises to near
/// full-screen (the add/edit forms); otherwise the sheet hugs its content
/// (management lists, Languages, Edit Cover, the photo sheet).
///
/// [useRootNavigator] puts the sheet over the home shell's floating nav, as the
/// app's other sheets do; it is off by default because most of these sheets
/// open from the full-screen edit surfaces.
Future<T?> showProfileSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool fullHeight = false,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    // The frame paints the pane. Without a plain shape here the theme's
    // `GlassBorder` would still draw its rim and shadow around the (clear)
    // modal surface — a second, ghost pane behind the real one.
    shape: const RoundedRectangleBorder(),
    // Barrier omitted so `BottomSheetThemeData.modalBarrierColor` applies and
    // follows the active brightness.
    builder: (sheetContext) => AppSheetFrame(
      fullHeight: fullHeight,
      child: builder(sheetContext),
    ),
  );
}

/// One row of a [showProfileActionSheet] menu.
class ProfileSheetAction<T> {
  const ProfileSheetAction({
    required this.value,
    required this.icon,
    required this.label,
    this.destructive = false,
    this.key,
  });

  /// What the sheet resolves to when this row is tapped.
  final T value;
  final IconData icon;
  final String label;

  /// Destructive rows take the destructive ink; the label still names the
  /// consequence, so the meaning survives greyscale and a screen reader.
  final bool destructive;

  /// A key for the row (widget tests find rows by it).
  final Key? key;
}

/// The profile's action menu — the "…" on a profile, an activity row's owner
/// menu, the member menu on someone else's profile — as the app's floating
/// actions card ([AppSheetFrame.floating]), with the same rows the chat
/// actions menu uses: a 21pt glyph and a label in one ink, destructive rows in
/// `destructiveInk`. Resolves to the tapped row's value, or null when
/// dismissed; the caller owns what each value does.
Future<T?> showProfileActionSheet<T>(
  BuildContext context, {
  required List<ProfileSheetAction<T>> actions,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    // See [showProfileSheet]: the floating card paints itself, and the
    // theme's glass shape would otherwise outline the full-width surface
    // behind it.
    shape: const RoundedRectangleBorder(),
    builder: (sheetContext) => AppSheetFrame.floating(
      child: _ActionSheetBody<T>(actions: actions),
    ),
  );
}

class _ActionSheetBody<T> extends StatelessWidget {
  const _ActionSheetBody({required this.actions});

  final List<ProfileSheetAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final safe = [
      for (final a in actions)
        if (!a.destructive) a
    ];
    final destructive = [
      for (final a in actions)
        if (a.destructive) a
    ];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          for (final action in safe) _ActionRow<T>(action: action),
          // The same break the chat menu draws between everyday rows and the
          // ones that end or report a relationship.
          if (safe.isNotEmpty && destructive.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: ProfileHairline(),
            ),
          for (final action in destructive) _ActionRow<T>(action: action),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionRow<T> extends StatelessWidget {
  const _ActionRow({required this.action});

  final ProfileSheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final ink = action.destructive ? tokens.destructiveInk : colors.onSurface;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: action.key,
          onTap: () => Navigator.of(context).pop(action.value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(action.icon, size: 21, color: ink),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      action.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The standard inner layout for a profile sheet: handle → top bar → scrollable
/// body → optional pinned footer (CTA). Used by every concrete sheet so the
/// chrome stays identical.
class ProfileSheetScaffold extends StatelessWidget {
  const ProfileSheetScaffold({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.doneLabel,
    this.onDone,
    this.tintedIcon = false,
    this.closeOnLeft = false,
    required this.body,
    this.footer,
    this.fullHeight = false,
  });

  final String title;

  /// The section glyph. Rendered in the neutral `iconInk` — the same tile and
  /// ink as the section header on the profile that opened this sheet, so the
  /// sheet reads as a continuation of that section rather than as a new,
  /// differently-coloured place.
  final IconData? icon;
  final String? subtitle;

  /// Forms show a back arrow that returns to their parent list.
  final bool showBack;
  final VoidCallback? onBack;

  /// Management lists show a "Done" commit pill in the header.
  final String? doneLabel;
  final VoidCallback? onDone;

  /// List sheets render the section icon in a soft tinted square.
  final bool tintedIcon;

  /// Puts the close (✕) button at the START of the header with nothing trailing
  /// (the Edit Project artboard uses this leading-close treatment).
  final bool closeOnLeft;

  final Widget body;
  final Widget? footer;
  final bool fullHeight;

  @override
  Widget build(BuildContext context) {
    final bodyScroll = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: body,
    );

    return Column(
      mainAxisSize: fullHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _SheetTopBar(
          title: title,
          subtitle: subtitle,
          icon: icon,
          tintedIcon: tintedIcon,
          showBack: showBack,
          onBack: onBack,
          doneLabel: doneLabel,
          onDone: onDone,
          closeOnLeft: closeOnLeft,
        ),
        const ProfileHairline(),
        if (fullHeight)
          Expanded(child: bodyScroll)
        else
          Flexible(child: bodyScroll),
        if (footer != null) _SheetFooter(child: footer!),
      ],
    );
  }
}

class _SheetTopBar extends StatelessWidget {
  const _SheetTopBar({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tintedIcon,
    required this.showBack,
    required this.onBack,
    required this.doneLabel,
    required this.onDone,
    required this.closeOnLeft,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool tintedIcon;
  final bool showBack;
  final VoidCallback? onBack;
  final String? doneLabel;
  final VoidCallback? onDone;
  final bool closeOnLeft;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: EdgeInsets.fromLTRB(closeOnLeft || showBack ? 8 : 18, 0, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (closeOnLeft) ...[
            _SheetHeaderAction(
              icon: Icons.close,
              tooltip: 'Close',
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
          ] else if (showBack) ...[
            _SheetHeaderAction(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
          ],
          if (icon != null) ...[
            if (tintedIcon)
              ProfileGlyphTile(icon: icon!, size: 30, iconSize: 17)
            else
              ExcludeSemantics(
                child: Icon(icon, size: 18, color: tokens.iconInk),
              ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: tokens.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (!closeOnLeft) ...[
            if (doneLabel != null) ...[
              // Done commits the sheet, so it is the primary action — the
              // app's compact primary button.
              AppButton.primary(
                label: doneLabel!,
                onPressed: onDone,
                expand: false,
                size: AppButtonSize.compact,
              ),
              const SizedBox(width: 4),
            ],
            _SheetHeaderAction(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ],
      ),
    );
  }
}

/// The header's close / back control: a quiet 48pt icon button in secondary
/// ink, the same one the app's other sheets (report, job link) carry. The
/// sheet already floats on its own pane; a second glass disc on it was one
/// more raised object competing with the title.
class _SheetHeaderAction extends StatelessWidget {
  const _SheetHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      color: context.colorScheme.onSurfaceVariant,
    );
  }
}

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The sheet's own pane shows through; only a hairline marks where the
    // scrolling body ends and the pinned actions begin.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ProfileHairline(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

// Buttons ---------------------------------------------------------------------

/// Full-width primary CTA — the bottom action on forms / Social Links /
/// Edit Cover ("Add Experience", "Start", "Apply Cover", …).
///
/// The app's primary [AppButton]: the lit near-white pane in dark, unlit when
/// [onTap] is null. [loading] keeps it lit with a spinner beside the caller's
/// in-progress wording, so a save in flight reads as "working", not as "dead".
class SheetPrimaryButton extends StatelessWidget {
  const SheetPrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return AppButton.primary(label: label, onPressed: onTap, loading: loading);
  }
}

/// Full-width "+ Add …" button — opens a nested add form from a management
/// list.
///
/// The app's secondary [AppButton]. It sits directly under a list whose
/// commit is the header's Done, so it must read as "also available", not as a
/// second primary.
class SheetOutlinedAddButton extends StatelessWidget {
  const SheetOutlinedAddButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton.secondary(
      label: label,
      leading: Icons.add,
      onPressed: onTap,
    );
  }
}

// Inputs ----------------------------------------------------------------------

/// The rule under a sheet field: the profile's strong hairline at rest (the
/// theme's `outlineVariant` is invisible on the overlay pane), the app's
/// neutral focus colour while the field has focus, the error colour when the
/// field is invalid. Thicker in either live state, so focus and error never
/// rest on colour alone.
class _FieldRule extends StatelessWidget {
  const _FieldRule({this.focused = false, this.error = false});

  final bool focused;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final t = ProfileSurfaceTokens.of(context);
    final color = error
        ? colors.error
        : (focused ? tokens.fieldFocusRim : t.hairlineStrong);
    final thickness = error || focused ? 1.5 : 1.0;
    return AnimatedContainer(
      duration: AppMotion.durationFor(context, AppMotion.state),
      height: thickness,
      color: color,
    );
  }
}

/// Underline text field with a label above and a rule beneath — the form
/// field treatment used across the profile sheets. When [errorText] is set the
/// rule turns red and the message renders beneath it, giving the sheets inline
/// per-field validation; while focused the rule takes the app's focus colour.
class SheetTextField extends StatefulWidget {
  const SheetTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
    this.keyboardType,
    this.leadingIcon,
    this.onChanged,
    this.errorText,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final int? maxLength;
  final bool showCounter;
  final TextInputType? keyboardType;

  /// Optional glyph shown to the left of the value (e.g. a link icon on a URL
  /// field). The rule still spans the full field width.
  final IconData? leadingIcon;

  /// Optional change callback (e.g. to drive an autocomplete).
  final ValueChanged<String>? onChanged;

  /// Inline validation message. Non-null = error state (red rule + text).
  final String? errorText;

  @override
  State<SheetTextField> createState() => _SheetTextFieldState();
}

class _SheetTextFieldState extends State<SheetTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final errorText = widget.errorText;
    final hasError = errorText != null && errorText.isNotEmpty;
    final maxLength = widget.maxLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: hasError ? colors.error : colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.leadingIcon != null) ...[
              Icon(widget.leadingIcon, size: 16, color: tokens.textTertiary),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                maxLines: widget.maxLines,
                minLines: widget.maxLines > 1 ? widget.maxLines : 1,
                maxLength: maxLength,
                keyboardType: widget.keyboardType,
                onChanged: widget.onChanged,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  // Opt out of the app-wide filled InputDecorationTheme: these
                  // sheets use underline fields drawn by [_FieldRule].
                  filled: false,
                  fillColor: Colors.transparent,
                  hintText: widget.hint,
                  hintStyle:
                      TextStyle(color: tokens.textTertiary, fontSize: 14.5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
                style: TextStyle(
                  fontSize: 14.5,
                  color: colors.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (widget.showCounter && maxLength != null)
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) => Text(
                '${value.text.length}/$maxLength',
                style: TextStyle(fontSize: 12, color: tokens.textTertiary),
              ),
            ),
          ),
        const SizedBox(height: 6),
        _FieldRule(focused: _focus.hasFocus, error: hasError),
        if (hasError) ...[
          const SizedBox(height: 5),
          Semantics(
            liveRegion: true,
            child: Text(
              errorText,
              style: TextStyle(fontSize: 11.5, color: colors.error),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tappable date field (label above, value/hint + calendar glyph, hairline
/// divider beneath) — the read-only twin of [SheetTextField] for month/year
/// pickers. [value] is the formatted display text; [onTap] opens the picker.
class SheetDateField extends StatelessWidget {
  const SheetDateField({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.onTap,
    this.enabled = true,
    this.errorText,
  });

  final String label;
  final String hint;
  final String value;
  final VoidCallback onTap;
  final bool enabled;

  /// Inline validation message. Non-null = error state (red divider + text).
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final hasValue = value.isNotEmpty;
    final hasError = errorText != null && errorText!.isNotEmpty;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        hasValue ? value : hint,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color:
                              hasValue ? colors.onSurface : tokens.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: tokens.textTertiary),
                ],
              ),
              const SizedBox(height: 6),
              _FieldRule(error: hasError),
              if (hasError) ...[
                const SizedBox(height: 5),
                Text(
                  errorText!,
                  style: TextStyle(fontSize: 11.5, color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable value field (label above, value/hint + trailing glyph, hairline
/// divider) for things picked in a sub-sheet rather than typed — e.g. a
/// location. Shows a clear (✕) affordance when a value is set and [onClear] is
/// given.
class SheetTapField extends StatelessWidget {
  const SheetTapField({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.onTap,
    this.trailingIcon = Icons.search,
    this.onClear,
  });

  final String label;
  final String hint;
  final String value;
  final VoidCallback onTap;
  final IconData trailingIcon;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final hasValue = value.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    hasValue ? value : hint,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: hasValue ? colors.onSurface : tokens.textTertiary,
                    ),
                  ),
                ),
              ),
              if (hasValue && onClear != null)
                Semantics(
                  button: true,
                  label: 'Clear $label',
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: onClear,
                    radius: 18,
                    child: SizedBox.square(
                      dimension: 32,
                      child: Icon(Icons.close,
                          size: 16, color: tokens.textTertiary),
                    ),
                  ),
                )
              else
                Icon(trailingIcon, size: 16, color: tokens.textTertiary),
            ],
          ),
          const SizedBox(height: 6),
          const _FieldRule(),
        ],
      ),
    );
  }
}

/// All-caps muted section label (e.g. "CARD ACCENT COLOR", "CHOOSE A GRADIENT").
class SheetSectionLabel extends StatelessWidget {
  const SheetSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: color ?? tokens.textTertiary,
      ),
    );
  }
}

/// Wrapping single-select chip group (Employment Type, Location Type, Grade,
/// Category, Proficiency Level), built from the app's filter chips.
class SheetChipGroup extends StatelessWidget {
  const SheetChipGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    // The chips pad their own targets to 48pt, so the runs need no gap.
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: [
        for (final option in options)
          _SelectChip(
            label: option,
            selected: option == selected,
            onTap: () => onSelected(option),
          ),
      ],
    );
  }
}

/// Wrapping **multi**-select chip group (the hands-on skills picker on the
/// Experience form). Same chip as [SheetChipGroup] so a selected skill reads
/// identically to a selected employment type; only the selection model
/// differs — [selected] is a set and [onToggle] flips one entry.
///
/// [ids] and [labels] are parallel: the chip shows the label, the caller works
/// in ids (skill uuids, which is what the write contract wants).
class SheetMultiSelectChipGroup extends StatelessWidget {
  const SheetMultiSelectChipGroup({
    super.key,
    required this.ids,
    required this.labels,
    required this.selected,
    required this.onToggle,
  });

  final List<String> ids;
  final List<String> labels;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: [
        for (var i = 0; i < ids.length && i < labels.length; i++)
          _SelectChip(
            label: labels[i],
            selected: selected.contains(ids[i]),
            onTap: () => onToggle(ids[i]),
          ),
      ],
    );
  }
}

/// One option in a [SheetChipGroup]: the app's filter chip (`AppChip.filter`)
/// — recessed when idle, lifted with full ink and a check when chosen — so a
/// choice in a profile sheet is the same object as a filter on Jobs.
class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppChip(
      label: label,
      variant: AppChipVariant.filter,
      selected: selected,
      icon: selected ? Icons.check_rounded : null,
      onTap: onTap,
    );
  }
}

/// Outlined removable chip with a category-colored border + trailing ✕ (the
/// skills editor / live entry chips).
class SheetRemovableChip extends StatelessWidget {
  const SheetRemovableChip({
    super.key,
    required this.label,
    required this.color,
    required this.onRemove,
  });

  final String label;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final t = ProfileSurfaceTokens.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: t.raisedFill,
        borderRadius: AppRadii.smallAll,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Remove $label',
            excludeSemantics: true,
            child: InkResponse(
              onTap: onRemove,
              radius: 16,
              child: SizedBox.square(
                dimension: 32,
                child:
                    Icon(Icons.close, size: 14, color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Square checkbox + label row ("Currently working here").
class SheetCheckboxRow extends StatelessWidget {
  const SheetCheckboxRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return MergeSemantics(
      child: Semantics(
        checked: value,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: _checkboxRow(colors, tokens),
        ),
      ),
    );
  }

  Widget _checkboxRow(ColorScheme colors, SyncUpSemantics tokens) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Checked is `controlInk` (brand in light, near-white in dark);
              // the tick is `onCtaFill`, which is the ink for that same fill
              // in both themes. Unchecked is the interactive line, so the box
              // still clears 3:1 as a control boundary.
              color: value ? tokens.controlInk : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: value ? tokens.controlInk : colors.outline,
                width: 1.5,
              ),
            ),
            child: value
                ? Icon(Icons.check, size: 14, color: tokens.onCtaFill)
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: colors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Card Accent Color" picker — a row of circular swatches (selection = ring +
/// check) plus a trailing dashed "+" custom affordance. [palette] is the
/// saturated set (Experience/Skill) or the pastel set (Education).
class AccentColorPicker extends StatelessWidget {
  const AccentColorPicker({
    super.key,
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final List<Color> palette;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetSectionLabel('Card Accent Color'),
        const SizedBox(height: 12),
        // One evenly-distributed control row (8 swatches + custom), rather than
        // a Wrap that drops the trailing "+" onto its own line.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final color in palette)
              _Swatch(
                color: color,
                selected: color == selected,
                onTap: () => onSelected(color),
              ),
            const _CustomSwatch(),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final t = ProfileSurfaceTokens.of(context);
    // Light pastels need a dark check; saturated swatches a white one — the
    // fixed media inks, since the swatch is the user's own colour in both
    // themes.
    final luminance = color.computeLuminance();
    final checkColor =
        luminance > 0.6 ? tokens.mediaSurface : tokens.onMediaSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          // The selection ring is the page's high-emphasis ink, so it reads
          // on the charcoal sheet; unselected swatches get the hairline.
          border: selected
              ? Border.all(color: colors.onSurface, width: 2.5)
              : Border.all(color: t.hairline),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: selected ? Icon(Icons.check, size: 15, color: checkColor) : null,
      ),
    );
  }
}

class _CustomSwatch extends StatelessWidget {
  const _CustomSwatch();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return DottedBorder(
      borderType: BorderType.Circle,
      color: tokens.textTertiary,
      strokeWidth: 1.4,
      dashPattern: const [4, 3],
      child: SizedBox(
        width: 30,
        height: 30,
        child: Icon(Icons.add, size: 15, color: tokens.textTertiary),
      ),
    );
  }
}

/// Honest, unobtrusive note that an unwired sheet's edits are a local preview
/// and aren't persisted to the backend yet. Keeps the UX truthful without
/// faking a save.
class SheetSyncNote extends StatelessWidget {
  const SheetSyncNote({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 13, color: tokens.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message ??
                "Preview only. Changes here aren't saved to your profile yet.",
            style: TextStyle(fontSize: 11.5, color: tokens.textTertiary),
          ),
        ),
      ],
    );
  }
}

/// Trailing edit (neutral) + delete (red) circular icon pair on management
/// rows. Laid out as a [Row] by default; pass [vertical] to stack them.
///
/// Edit is a raised neutral disc with `controlInk`; delete keeps the semantic
/// red pair. The two used to be indigo and red side by side, which made every
/// row carry two competing colours for what are a routine and a destructive
/// action respectively.
class SheetRowActions extends StatelessWidget {
  const SheetRowActions({
    super.key,
    required this.onEdit,
    required this.onDelete,
    this.vertical = false,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final t = ProfileSurfaceTokens.of(context);
    final children = [
      _RoundAction(
        icon: Icons.edit_outlined,
        label: 'Edit',
        fill: t.raisedFill,
        color: tokens.controlInk,
        onTap: onEdit,
      ),
      SizedBox(width: vertical ? 0 : 8, height: vertical ? 8 : 0),
      _RoundAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        fill: colors.errorContainer,
        color: tokens.destructiveInk,
        onTap: onDelete,
      ),
    ];
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.fill,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color fill;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}
