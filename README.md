# SyncUp — User Profile

The user-profile feature of the SyncUp Flutter app, redesigned: a strict
black-and-white theme, an animated left-aligned hero, folding sections with a
"Show more" line, bare company logos in Experience, icon-only social links,
and stacked project cards.

## Contents

- `lib/features/profile/` — the profile feature (screens, widgets, data, providers)
  - `widgets/profile_hero.dart` — hero: cover parallax, avatar halo, stats, liquid-glass "…" menu
  - `widgets/profile_section.dart` — section layout and the fold (first items shown, the rest behind "Show N more")
  - `widgets/profile_motion.dart` — entrance reveals, count-up, pulse, orbit ring, shimmer
  - `widgets/profile_view_sections.dart` — icon-only links, bio, intro video, experience, education, skills…
  - `widgets/profile_entry_cards.dart` — experience entries with company logos
- `lib/core/theme/` — the monochrome theme the profile uses (`AppTheme.profileMono`)
- `lib/main_profile_preview.dart` + `lib/preview/` — a standalone preview on sample data

These files are part of the larger SyncUp app and import its shared code
(`lib/core`, `lib/shared`, other features), so they do not build on their own.

Preview (inside the full app):

```
flutter build web -t lib/main_profile_preview.dart
```
