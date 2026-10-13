import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Puts a profile surface on the strict black-and-white theme
/// ([AppTheme.profileMono]) whatever the app's theme mode is.
///
/// Wrapped around the route, not inside the screen, so the screen's own
/// `BuildContext` — and with it every sheet, dialog and snackbar it opens
/// (`showModalBottomSheet` captures the caller's theme) — is monochrome too.
class ProfileMonoTheme extends StatelessWidget {
  const ProfileMonoTheme({super.key, required this.child});

  final Widget child;

  static final ThemeData _theme = AppTheme.profileMono;

  @override
  Widget build(BuildContext context) => Theme(data: _theme, child: child);
}
