/// Pure display mapping for activity rows — kept out of the widgets so the
/// label rules and HTML cleanup are unit-testable.
library;

import '../../../core/helpers/html_text.dart';
import '../../post/data/models/post_models.dart' show Activity;

/// The only activity `type` used as a request filter today (the Posts tab).
const String kActivityTypePostCreated = 'POST_CREATED';

/// Human-readable action line for an activity ("created a post").
///
/// Only values confirmed against the staging contract/UI copy are mapped;
/// anything else falls back to a cleaned version of the raw `action` (then
/// `type`) so an unknown backend value renders as a generic-but-honest row
/// instead of crashing or showing SCREAMING_SNAKE_CASE.
String activityActionLabel(Activity activity) {
  switch (activity.type.trim().toUpperCase()) {
    case 'POST_CREATED':
      return 'created a post';
    case 'POST_COMMENTED':
      return 'commented on a post';
    case 'POST_LIKED':
      return 'liked a post';
    case 'JOB_APPLIED':
      return 'applied for a job';
    case 'CONNECTION_CREATED':
      return 'connected with someone';
  }
  final action = _humanize(activity.action);
  if (action.isNotEmpty) return action;
  return _humanize(activity.type);
}

/// `POST_SHARED` → `post shared`, `commented` → `commented`, '' → ''.
String _humanize(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Plain-text target title ("&lt;p&gt;Nature&lt;/p&gt;" → "Nature"); empty
/// when the activity has none.
String activityTargetLabel(Activity activity) =>
    htmlToPlainText(activity.targetTitle);

/// Plain-text description; empty when the activity has none.
String activityDescriptionLabel(Activity activity) =>
    htmlToPlainText(activity.description);

/// True when the activity is PUBLIC (shown to other viewers). Unknown/missing
/// visibility values are treated as NOT public — an uncertain activity must
/// never leak onto a visitor-facing surface.
bool activityIsPublic(Activity activity) =>
    activity.visibility.trim().toUpperCase() == 'PUBLIC';
