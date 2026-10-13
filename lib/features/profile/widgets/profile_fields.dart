import 'package:flutter/material.dart';

import '../../../core/utils/form_validators.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';

class BasicInfoField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final bool showDivider;

  /// When true the value is shown but not editable (no documented write route
  /// for this field). A small [note] explains why so the UI stays honest.
  final bool readOnly;
  final String? note;

  /// When set, the field becomes a tappable picker (value shown, not typed):
  /// tapping opens [onTap] and a search glyph replaces the lock.
  final VoidCallback? onTap;

  /// Inline validation message. Non-null = error state (red divider + text).
  final String? errorText;

  /// Change callback (e.g. to clear [errorText] once the user edits).
  final ValueChanged<String>? onChanged;

  /// Hard cap on typed input. When set, the field stops accepting characters
  /// past it and a counter fades in near the limit — the same shape the
  /// website's edit-profile fields use. Null leaves the field uncapped.
  final int? maxLength;

  /// Lets the screen put the cursor here when a save is refused because of
  /// this field, instead of only saying that *some* field is wrong.
  final FocusNode? focusNode;

  const BasicInfoField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.showDivider = true,
    this.readOnly = false,
    this.note,
    this.onTap,
    this.errorText,
    this.onChanged,
    this.maxLength,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final isPicker = onTap != null;
    final hasError = errorText != null && errorText!.isNotEmpty;
    // A picker is display-only (tap to change) but not "locked".
    final fieldReadOnly = readOnly || isPicker;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      readOnly: fieldReadOnly,
      enableInteractiveSelection: !fieldReadOnly,
      onChanged: onChanged,
      maxLength: maxLength,
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        // Material's own counter would sit below the divider and add height to
        // every row; the label row carries ours only when it is relevant.
        counterText: '',
      ),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: (readOnly && !isPicker) ? tokens.textTertiary : colors.onSurface,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: showDivider ? 9 : 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  // The label turns with the rule and the message: "fix the
                  // highlighted fields" has to be true of the field itself.
                  color: hasError ? colors.error : tokens.textTertiary,
                ),
              ),
              if (maxLength != null) ...[
                const Spacer(),
                _NearLimitCounter(
                  controller: controller,
                  maxLength: maxLength!,
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(icon, size: 14, color: tokens.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: isPicker
                    ? GestureDetector(
                        onTap: onTap,
                        behavior: HitTestBehavior.opaque,
                        child: IgnorePointer(child: field),
                      )
                    : field,
              ),
              if (isPicker)
                Icon(Icons.search, size: 14, color: tokens.textTertiary)
              else if (readOnly)
                Icon(Icons.lock_outline, size: 12, color: tokens.textTertiary),
            ],
          ),
          if (hasError) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  errorText!,
                  style: TextStyle(fontSize: 10.5, color: colors.error),
                ),
              ),
            ),
          ] else if (note != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                note!,
                style: TextStyle(fontSize: 10.5, color: tokens.textTertiary),
              ),
            ),
          ],
          // A row that normally ends its card without a rule (Website) still
          // gets the red one in error, or its only highlight would be 10pt text.
          if (showDivider || hasError) ...[
            const SizedBox(height: 7),
            Divider(
                height: 1,
                thickness: hasError ? 1.5 : 1,
                color: hasError
                    ? colors.error
                    : ProfileSurfaceTokens.of(context).hairline),
          ],
        ],
      ),
    );
  }
}

class AboutBioField extends StatelessWidget {
  final TextEditingController controller;

  /// Inline validation message set by the parent at save time (e.g. bio too
  /// short). Non-null = error state.
  final String? errorText;

  /// Change callback (e.g. to clear [errorText] once the user edits).
  final ValueChanged<String>? onChanged;

  /// Hard cap on typed input. When set, the field stops accepting characters
  /// past it and a counter fades in near the limit — the same shape the
  /// website's edit-profile fields use. Null leaves the field uncapped.
  final int? maxLength;

  /// See [BasicInfoField.focusNode].
  final FocusNode? focusNode;

  const AboutBioField({
    super.key,
    required this.controller,
    this.errorText,
    this.onChanged,
    this.maxLength,
    this.focusNode,
  });

  static const int _min = FormValidators.bioMinLength;
  static const int _max = FormValidators.bioMaxLength;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final hasError = errorText != null && errorText!.isNotEmpty;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final length = value.text.length;
        // Live guidance while the bio is still below the minimum; the red
        // save-time error (from the parent) takes precedence.
        final remaining = _min - value.text.trim().length;
        final showMinHint = !hasError && length > 0 && remaining > 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'BIO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: hasError ? colors.error : tokens.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  '$length/$_max',
                  style: TextStyle(
                    fontSize: 11,
                    color: hasError ? colors.error : tokens.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 82,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: null,
                expands: true,
                maxLength: _max,
                onChanged: onChanged,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText:
                      'Tell people about yourself: your role, what you\'ve '
                      'built, and what you\'re looking for.',
                  hintStyle: TextStyle(
                    color: tokens.textTertiary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  counterText: '',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            if (hasError) ...[
              // Same red rule the Basic Info rows close on, so the bio reads as
              // highlighted rather than as a plain box with a caption under it.
              Divider(height: 1, color: colors.error),
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: Text(
                  errorText!,
                  style: TextStyle(fontSize: 11.5, color: colors.error),
                ),
              ),
            ] else if (showMinHint) ...[
              const SizedBox(height: 4),
              Text(
                'At least $_min characters - $remaining more to go.',
                style: TextStyle(fontSize: 11.5, color: tokens.textTertiary),
              ),
            ],
          ],
        );
      },
    );
  }
}

class OpenToWorkRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const OpenToWorkRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open to Work',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "Let recruiters know you're available",
                  style: TextStyle(
                    fontSize: 11.5,
                    color: tokens.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // The app's switch theme, unmodified: the same control as every
          // other on/off setting.
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Character counter that appears only as the value approaches its limit.
///
/// Mirrors the website's edit-profile fields, which render the counter when
/// `length >= MAX - 20` and turn it red at the limit
/// (`PersonalInformation.tsx`, `ProfileTaglineBio.tsx`). Keeping it hidden the
/// rest of the time is the point: a 12-character name should not be trailed by
/// "12/50" it will never reach.
class _NearLimitCounter extends StatelessWidget {
  const _NearLimitCounter({required this.controller, required this.maxLength});

  final TextEditingController controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // Trimmed, like the website: trailing spaces shouldn't trip the warning.
        final length = value.text.trim().length;
        if (length < maxLength - FormValidators.counterRevealWindow) {
          return const SizedBox.shrink();
        }
        return Text(
          '$length/$maxLength',
          style: TextStyle(
            fontSize: 10,
            fontWeight: length >= maxLength ? FontWeight.w700 : FontWeight.w500,
            color: length >= maxLength ? colors.error : tokens.textTertiary,
          ),
        );
      },
    );
  }
}
