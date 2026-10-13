import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_manager.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/helpers/snackbar_helper.dart';
import '../../../core/helpers/work_link_url.dart';
import '../../../shared/widgets/work_links_editor.dart';
import '../../../core/utils/form_validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_chip.dart';
import '../../../shared/widgets/app_segmented.dart';
import '../../../shared/widgets/month_year_picker.dart';
import '../../home/providers/feed_provider.dart';
import '../../profile_menu/providers/profile_menu_provider.dart';
import '../data/models/profile_links.dart';
import '../data/models/user_profile.dart';
import '../data/projects_repository.dart';
import '../data/resume_sections_repository.dart';
import '../providers/profile_provider.dart';
import 'location_picker_sheet.dart';
import 'profile_entry_cards.dart';
import 'profile_sheet_kit.dart';
import 'profile_surface.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/theme/theme_context_ext.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Profile edit/add sheets
///
/// The concrete bottom sheets behind the profile section "Add / Edit"
/// affordances, built from `SyncUp_Profile_Edit_Screens_Design_Spec.md`:
/// Social Links, Experience (list + form), Education (list + form), Skills
/// (categorized + form), Languages (list + form), and Edit Cover (Color +
/// Photo). The shared chrome/primitives live in `profile_sheet_kit.dart`.
///
/// Persistence scope:
///   • Skills + Languages are LIVE — they persist through
///     [ResumeSectionsRepository] (skill create-batch / delete-batch and the
///     languages whole-list PUT) and invalidate `myProfileProvider` so the
///     save round-trips onto the profile.
///   • Experience, Education, Projects, Social Links and Edit Cover are still
///     UI-only: they work on a local in-session copy and stay honest about it
///     (a [SheetSyncNote] + an honest toast on commit) rather than faking a
///     save. They're blocked on record-id plumbing (update/delete target a
///     record id `ProfileEntry` doesn't carry yet) and a real date picker
///     (the forms use free-text dates, not the ISO `startMonthYear`/`startDate`
///     the create endpoints want). The field sets here already mirror those
///     contracts for that later pass.
/// ─────────────────────────────────────────────────────────────────────────

const String _kNotSavedMessage =
    "Editing isn't connected yet, so your changes weren't saved.";

void _honestToast(BuildContext context, [String message = _kNotSavedMessage]) {
  // Route through the branded top snack bar so honest/validation notices match
  // the success/error toasts and the rest of the app.
  showSnackbar(context, message);
}

// ── Public entry points (called from the wired affordances) ──────────────────

Future<void> openExperienceSheet(
    BuildContext context, List<ProfileEntry> seed) {
  return showProfileSheet(context,
      builder: (_) => _ExperienceListSheet(seed: seed));
}

Future<void> openEducationSheet(BuildContext context, List<ProfileEntry> seed) {
  return showProfileSheet(context,
      builder: (_) => _EducationListSheet(seed: seed));
}

Future<void> openSkillsSheet(
  BuildContext context,
  Map<String, List<String>> seed,
  Map<String, String> seedColors,
) {
  return showProfileSheet(context,
      builder: (_) => _SkillsSheet(seed: seed, seedColors: seedColors));
}

Future<void> openLanguagesSheet(
    BuildContext context, List<LanguageEntry> seed) {
  return showProfileSheet(context,
      builder: (_) => _LanguagesListSheet(seed: seed));
}

Future<void> openSocialLinksSheet(BuildContext context, ProfileLinks links) {
  return showProfileSheet(context,
      fullHeight: true, builder: (_) => _SocialLinksSheet(seed: links));
}

Future<void> openEditCoverSheet(BuildContext context) {
  return showProfileSheet(context, builder: (_) => const _EditCoverSheet());
}

/// Add (when [project] is null) / Edit one Proof of Work entry.
///
/// "Proof of Work" is the website's profile-facing name for this section; the
/// backend resource, its routes and `ProjectEntry`/`ProjectInput` stay
/// `project` so nothing on the wire or in onboarding has to move.
Future<void> openProjectSheet(BuildContext context, {ProjectEntry? project}) {
  return showProfileSheet(
    context,
    fullHeight: true,
    builder: (_) => _ProjectFormSheet(initial: project),
  );
}

/// Bottom sheet to change / remove the profile photo. Uses the shared photo
/// picker + presigned upload, then invalidates the profile so the new avatar
/// shows live.
Future<void> openProfilePhotoSheet(BuildContext context) {
  return showProfilePhotoSheet(context, isBanner: false);
}

// ── Shared helpers ───────────────────────────────────────────────────────────

double _proficiencyProgress(String level) {
  switch (level.toLowerCase()) {
    case 'native':
      return 1.0;
    case 'fluent':
      return 0.85;
    case 'professional':
      return 0.8;
    case 'intermediate':
      return 0.6;
    case 'conversational':
      return 0.45;
    default:
      return 0.55;
  }
}

const List<String> _kProficiencyLevels = [
  'Native',
  'Professional',
  'Intermediate',
  'Conversational',
];

/// Coerces a level to one of the API's accepted proficiency enum values so a
/// whole-list languages PUT never sends an unsupported value (e.g. a legacy
/// "Fluent" seed). Unknown levels fall back to the closest documented enum.
String _normalizeProficiency(String level) {
  final match = _kProficiencyLevels.firstWhere(
    (p) => p.toLowerCase() == level.trim().toLowerCase(),
    orElse: () => '',
  );
  if (match.isNotEmpty) return match;
  switch (level.trim().toLowerCase()) {
    case 'fluent':
    case 'advanced':
      return 'Professional';
    case 'basic':
    case 'beginner':
      return 'Conversational';
    default:
      return 'Professional';
  }
}

const List<String> _kEmploymentTypes = [
  'Full-time',
  'Part-time',
  'Contract',
  'Freelance',
  'Internship',
];

const List<String> _kLocationTypes = ['On-site', 'Remote', 'Hybrid'];

// ── Enum ↔ display-label mappers (resume-service contracts) ───────────────────

const Map<String, String> _kWorkModeByLabel = {
  'Full-time': 'fulltime',
  'Part-time': 'parttime',
  'Contract': 'contract',
  'Freelance': 'freelance',
  'Internship': 'internship',
};

String _workModeEnum(String label) => _kWorkModeByLabel[label] ?? 'fulltime';

String _workModeLabel(String? value) {
  for (final e in _kWorkModeByLabel.entries) {
    if (e.value == value) return e.key;
  }
  return '';
}

const Map<String, String> _kLocationTypeByLabel = {
  'On-site': 'onsite',
  'Remote': 'remote',
  'Hybrid': 'hybrid',
};

String _locationTypeEnum(String label) =>
    _kLocationTypeByLabel[label] ?? 'onsite';

String _locationTypeLabel(String? value) {
  for (final e in _kLocationTypeByLabel.entries) {
    if (e.value == value) return e.key;
  }
  return '';
}

/// `Color` → `#RRGGBB` for the backend `accentColor` field. The inverse
/// (`#RRGGBB` → `Color`) reuses the shared [profileAccentFromHex] from
/// `profile_entry_cards.dart` rather than a second local parser.
String _colorToHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

const List<String> _kGrades = ['Distinction', 'First Class'];
const List<String> _kDefaultSkillCategories = [
  'Design',
  'Research',
  'Tools',
  'Management',
];

/// Local curated skill suggestions. There's no backend skill-name search
/// endpoint (only category prefix-autocomplete), so these are an honest
/// client-side source to speed up entry — the user can still type anything.
const List<String> _kCommonSkills = [
  'Figma',
  'Sketch',
  'Adobe XD',
  'Photoshop',
  'Illustrator',
  'After Effects',
  'Prototyping',
  'Wireframing',
  'User Research',
  'Usability Testing',
  'Design Systems',
  'UI Design',
  'UX Design',
  'Interaction Design',
  'Flutter',
  'Dart',
  'React',
  'React Native',
  'JavaScript',
  'TypeScript',
  'Node.js',
  'Python',
  'Java',
  'Kotlin',
  'Swift',
  'SQL',
  'Firebase',
  'AWS',
  'Docker',
  'Git',
  'REST APIs',
  'GraphQL',
  'HTML',
  'CSS',
  'Tailwind CSS',
  'Product Management',
  'Agile',
  'Scrum',
  'Stakeholder Management',
  'Communication',
  'Leadership',
  'Data Analysis',
  'Machine Learning',
];

// ════════════════════════════════════════════════════════════════════════════
// Experience
// ════════════════════════════════════════════════════════════════════════════

class _ExpItem {
  String? id;
  String jobTitle;
  String company;
  String employmentType;
  DateTime? start;
  DateTime? end;
  bool currentlyWorking;
  String locationType;
  String? locationId;
  String locationLabel;
  String description;
  Color accent;
  final String? seededMeta;

  /// Read off the record and echoed back untouched on save — the app has no
  /// input for it. See [ProfileEntry.companyWebsite] for why omitting it would
  /// erase a website set on the web.
  final String? companyWebsite;

  /// Hands-on skills currently linked to this role.
  List<ProfileSkill> usedSkills;

  /// True once the user has touched the skills picker in this session.
  ///
  /// Gates whether `usedSkills` is sent at all: the field is a full replace
  /// server-side, so an untouched edit must omit it rather than resend what it
  /// happened to read — otherwise a stale local copy could quietly clear
  /// selections made on the website.
  bool skillsEdited;

  _ExpItem({
    this.id,
    required this.jobTitle,
    required this.company,
    this.employmentType = '',
    this.start,
    this.end,
    this.currentlyWorking = false,
    this.locationType = '',
    this.locationId,
    this.locationLabel = '',
    this.description = '',
    this.accent = const Color(0xFF6366F1),
    this.seededMeta,
    this.companyWebsite,
    this.usedSkills = const [],
    this.skillsEdited = false,
  });

  factory _ExpItem.fromEntry(ProfileEntry e) => _ExpItem(
        id: e.id,
        jobTitle: e.title,
        company: e.subtitle,
        employmentType: _workModeLabel(e.workMode),
        start: e.startDate,
        end: e.endDate,
        currentlyWorking: e.currentlyWorking ||
            (e.trailingBadge ?? '').toLowerCase() == 'now',
        locationType: _locationTypeLabel(e.locationType),
        locationId: e.locationId,
        locationLabel: e.locationLabel ?? '',
        description:
            e.description ?? (e.bullets.isNotEmpty ? e.bullets.first : ''),
        accent:
            profileAccentFromHex(e.accentColorHex) ?? kSaturatedAccents.first,
        seededMeta: e.meta,
        companyWebsite: e.companyWebsite,
        usedSkills: e.usedSkills,
      );

  String get metaLine {
    String dates;
    if (start != null) {
      final endLabel = currentlyWorking ? 'Present' : formatMonthYear(end);
      dates = endLabel.isNotEmpty
          ? '${formatMonthYear(start)} – $endLabel'
          : formatMonthYear(start);
    } else {
      dates = seededMeta ?? '';
    }
    return [
      if (dates.isNotEmpty) dates,
      if (employmentType.isNotEmpty) employmentType,
    ].join(' · ');
  }

  String get locationLine => locationType;

  /// [includeUsedSkills] carries the "did the user actually touch the picker?"
  /// decision down to the payload — see [skillsEdited] and
  /// [ExperienceInput.usedSkillIds].
  ExperienceInput toInput({bool includeUsedSkills = false}) => ExperienceInput(
        jobTitle: jobTitle,
        companyName: company,
        workMode: _workModeEnum(employmentType),
        locationType: _locationTypeEnum(locationType),
        startDate: start,
        endDate: end,
        currentlyWorking: currentlyWorking,
        jobDescription: description,
        accentColorHex: _colorToHex(accent),
        locationId: locationId,
        companyWebsite: companyWebsite,
        usedSkillIds:
            includeUsedSkills ? [for (final s in usedSkills) s.id] : null,
      );
}

class _ExperienceListSheet extends ConsumerStatefulWidget {
  const _ExperienceListSheet({required this.seed});

  final List<ProfileEntry> seed;

  @override
  ConsumerState<_ExperienceListSheet> createState() =>
      _ExperienceListSheetState();
}

class _ExperienceListSheetState extends ConsumerState<_ExperienceListSheet> {
  late final List<_ExpItem> _items =
      widget.seed.map(_ExpItem.fromEntry).toList();
  int? _deletingIndex;

  /// The form persists (create/update) and returns the saved item; we mirror it
  /// locally so the open list reflects the change immediately (the profile
  /// behind has already been invalidated by the form).
  Future<void> _openForm({int? index}) async {
    final result = await showProfileSheet<_ExpItem>(
      context,
      fullHeight: true,
      builder: (_) =>
          _ExperienceFormSheet(initial: index == null ? null : _items[index]),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _items.add(result);
      } else {
        _items[index] = result;
      }
    });
  }

  Future<void> _delete(int index) async {
    final item = _items[index];
    // Locally-added-but-unsaved rows have no id; just drop them.
    if (item.id == null) {
      setState(() => _items.removeAt(index));
      return;
    }
    setState(() => _deletingIndex = index);
    try {
      await ref
          .read(resumeSectionsRepositoryProvider)
          .deleteExperience(item.id!);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      setState(() {
        _items.removeAt(index);
        _deletingIndex = null;
      });
      context.showSnackBar('Experience removed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingIndex = null);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _deletingIndex != null;
    return ProfileSheetScaffold(
      title: 'Experience',
      icon: Icons.work_outline,
      tintedIcon: false,
      doneLabel: 'Done',
      onDone: busy ? null : () => Navigator.of(context).pop(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ExpCard(
                item: _items[i],
                accent: _railColor(i),
                onEdit: busy ? () {} : () => _openForm(index: i),
                onDelete: busy ? () {} : () => _delete(i),
              ),
            ),
          const SizedBox(height: 2),
          SheetOutlinedAddButton(
            label: 'Add Experience',
            onTap: busy ? null : () => _openForm(),
          ),
        ],
      ),
    );
  }

  /// The entry's chosen accent, or null for the neutral rail. The sentinel is
  /// `_ExpItem.accent`'s default, which means "nothing chosen" — such entries
  /// used to be colour-coded by order (indigo → blue → amber), a rainbow the
  /// profile view no longer paints either.
  Color? _railColor(int i) {
    final item = _items[i];
    return item.accent == const Color(0xFF6366F1) ? null : item.accent;
  }
}

class _ExpCard extends StatelessWidget {
  const _ExpCard({
    required this.item,
    required this.accent,
    required this.onEdit,
    required this.onDelete,
  });

  final _ExpItem item;

  /// The saved accent, or null for the neutral rail and company line.
  final Color? accent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final meta = item.metaLine;
    final loc = item.locationLine;
    final rail = accent ?? tokens.lineInteractive;
    final companyInk = accent ?? colors.onSurfaceVariant;
    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              width: 4,
              height: 104,
              decoration: BoxDecoration(
                color: rail,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.jobTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.company,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: companyInk,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta,
                      style: TextStyle(
                          fontSize: 11.5, color: tokens.textTertiary)),
                ],
                if (loc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(loc,
                      style: TextStyle(
                          fontSize: 11.5, color: tokens.textTertiary)),
                ],
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: colors.onSurface, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SheetRowActions(
              vertical: true,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperienceFormSheet extends ConsumerStatefulWidget {
  const _ExperienceFormSheet({this.initial});

  final _ExpItem? initial;

  @override
  ConsumerState<_ExperienceFormSheet> createState() =>
      _ExperienceFormSheetState();
}

class _ExperienceFormSheetState extends ConsumerState<_ExperienceFormSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initial?.jobTitle ?? '');
  late final TextEditingController _company =
      TextEditingController(text: widget.initial?.company ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.initial?.description ?? '');

  late DateTime? _start = widget.initial?.start;
  late DateTime? _end = widget.initial?.end;
  late String _employmentType =
      widget.initial?.employmentType.isNotEmpty == true
          ? widget.initial!.employmentType
          : 'Full-time';
  late String _locationType = widget.initial?.locationType.isNotEmpty == true
      ? widget.initial!.locationType
      : 'On-site';
  late bool _currentlyWorking = widget.initial?.currentlyWorking ?? false;
  late Color _accent = widget.initial?.accent ?? kSaturatedAccents.first;
  late String? _locationId = widget.initial?.locationId;
  late String _locationLabel = widget.initial?.locationLabel ?? '';
  bool _saving = false;

  /// Skill ids linked to this role. Seeded from the record so an edit opens
  /// with the website's selection already ticked.
  late final Set<String> _usedSkillIds = {
    for (final s in widget.initial?.usedSkills ?? const <ProfileSkill>[]) s.id,
  };

  /// Flipped the first time a chip is tapped. Until then the save omits
  /// `usedSkills` entirely, so editing (say) a job title on mobile can't clear
  /// skills picked on the web.
  bool _skillsEdited = false;

  // Inline per-field validation state; cleared as soon as the field changes.
  String? _titleError;
  String? _startError;
  String? _endError;

  @override
  void dispose() {
    _title.dispose();
    _company.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final loc = await showLocationPicker(context);
    if (loc != null && mounted) {
      setState(() {
        _locationId = loc.id;
        _locationLabel = loc.label;
      });
    }
  }

  Future<void> _pickStart() async {
    final picked = await showMonthYearPicker(context,
        initial: _start, title: 'Start date');
    if (picked != null) {
      setState(() {
        _start = picked;
        _startError = null;
        _endError = null;
      });
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showMonthYearPicker(context,
        initial: _end ?? _start, title: 'End date');
    if (picked != null) {
      setState(() {
        _end = picked;
        _endError = null;
      });
    }
  }

  /// The signed-in user's own skills — the only thing this picker may offer.
  ///
  /// Per-role skills are *links* to existing resume skills, not new ones: the
  /// write contract takes skill ids, and there is no create-and-link call. So
  /// the form never invents a skill; a user with none is sent to the Skills
  /// section first (see the empty state below), matching the website.
  ///
  /// Falls back to the skills already on this record when the profile hasn't
  /// resolved, so an edit can still show — and keep — what is linked today.
  List<ProfileSkill> _skillCatalog() {
    final catalog = ref.watch(myProfileProvider).value?.skillCatalog;
    if (catalog != null && catalog.isNotEmpty) return catalog;
    return widget.initial?.usedSkills ?? const [];
  }

  /// Validates the form inline. Returns true when it may be submitted.
  bool _validate() {
    final titleError = FormValidators.requiredField(_title.text) == null
        ? null
        : 'Add a job title to continue.';
    final startError = _start == null ? 'Select a start date.' : null;
    String? endError;
    if (!_currentlyWorking &&
        _start != null &&
        _end != null &&
        _end!.isBefore(_start!)) {
      endError = "End date can't be before the start date.";
    }
    setState(() {
      _titleError = titleError;
      _startError = startError;
      _endError = endError;
    });
    return titleError == null && startError == null && endError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final catalog = _skillCatalog();
    final item = _ExpItem(
      id: widget.initial?.id,
      jobTitle: _title.text.trim(),
      company: _company.text.trim(),
      employmentType: _employmentType,
      start: _start,
      end: _currentlyWorking ? null : _end,
      currentlyWorking: _currentlyWorking,
      locationType: _locationType,
      locationId: _locationId,
      locationLabel: _locationLabel,
      description: _description.text.trim(),
      accent: _accent,
      companyWebsite: widget.initial?.companyWebsite,
      usedSkills: [
        for (final skill in catalog)
          if (_usedSkillIds.contains(skill.id)) skill,
      ],
      skillsEdited: _skillsEdited,
    );

    final repo = ref.read(resumeSectionsRepositoryProvider);
    setState(() => _saving = true);
    try {
      if (item.id == null) {
        // A new record has no server-side selection to protect, so send
        // whatever the picker holds (including nothing).
        item.id = await repo.createExperience(
          item.toInput(includeUsedSkills: true),
        );
      } else {
        await repo.updateExperience(
          item.id!,
          item.toInput(includeUsedSkills: _skillsEdited),
        );
      }
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      // Show before popping: the snack bar rides the app-level messenger, which
      // outlives this sheet.
      context.showSnackBar(
          widget.initial == null ? 'Experience added' : 'Experience saved');
      Navigator.of(context).pop(item);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return ProfileSheetScaffold(
      title: 'Experience',
      icon: Icons.work_outline,
      fullHeight: true,
      showBack: true,
      footer: SheetPrimaryButton(
        label: _saving
            ? 'Saving…'
            : (editing ? 'Save Experience' : 'Add Experience'),
        onTap: _saving ? null : _submit,
        loading: _saving,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTextField(
            label: 'Job Title',
            hint: 'e.g. Senior Product Designer',
            controller: _title,
            errorText: _titleError,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Company',
            hint: 'Company name',
            controller: _company,
          ),
          const SizedBox(height: 18),
          Text('Employment Type', style: _formLabelStyle(context)),
          const SizedBox(height: 10),
          SheetChipGroup(
            options: _kEmploymentTypes,
            selected: _employmentType,
            onSelected: (v) => setState(() => _employmentType = v),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SheetDateField(
                  label: 'Start Date',
                  hint: 'Select month',
                  value: formatMonthYear(_start),
                  onTap: _pickStart,
                  errorText: _startError,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SheetDateField(
                  label: 'End Date',
                  hint: 'Select month',
                  value: formatMonthYear(_end),
                  onTap: _pickEnd,
                  enabled: !_currentlyWorking,
                  errorText: _endError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SheetCheckboxRow(
            label: 'Currently working here',
            value: _currentlyWorking,
            onChanged: (v) => setState(() {
              _currentlyWorking = v;
              if (v) _endError = null;
            }),
          ),
          const SizedBox(height: 18),
          Text('Location Type', style: _formLabelStyle(context)),
          const SizedBox(height: 10),
          SheetChipGroup(
            options: _kLocationTypes,
            selected: _locationType,
            onSelected: (v) => setState(() => _locationType = v),
          ),
          const SizedBox(height: 18),
          SheetTapField(
            label: 'Location',
            hint: 'Search a city',
            value: _locationLabel,
            trailingIcon: Icons.search,
            onTap: _pickLocation,
            onClear: () => setState(() {
              _locationId = null;
              _locationLabel = '';
            }),
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Description',
            hint: 'What did you achieve here?',
            controller: _description,
            maxLines: 3,
            maxLength: 300,
            showCounter: true,
          ),
          const SizedBox(height: 18),
          _HandsOnSkillsPicker(
            catalog: _skillCatalog(),
            selected: _usedSkillIds,
            onToggle: (id) => setState(() {
              _skillsEdited = true;
              if (!_usedSkillIds.remove(id)) _usedSkillIds.add(id);
            }),
          ),
          const SizedBox(height: 18),
          AccentColorPicker(
            palette: kSaturatedAccents,
            selected: _accent,
            onSelected: (c) => setState(() => _accent = c),
          ),
        ],
      ),
    );
  }
}

/// "Skills used in this role" — a multi-select over the user's *existing*
/// profile skills.
///
/// Nothing here creates a skill. The backend links a role to skill rows that
/// already belong to the resume, so an empty catalogue is a real dead end and
/// says so, pointing at the Skills section rather than offering a text field
/// that couldn't be saved.
class _HandsOnSkillsPicker extends StatelessWidget {
  const _HandsOnSkillsPicker({
    required this.catalog,
    required this.selected,
    required this.onToggle,
  });

  final List<ProfileSkill> catalog;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Skills used in this role', style: _formLabelStyle(context)),
        const SizedBox(height: 10),
        if (catalog.isEmpty)
          Text(
            'Add skills to your profile first, then link them to this role.',
            style: TextStyle(fontSize: 12.5, color: tokens.textTertiary),
          )
        else
          SheetMultiSelectChipGroup(
            ids: [for (final skill in catalog) skill.id],
            labels: [for (final skill in catalog) skill.name],
            selected: selected,
            onToggle: onToggle,
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Education
// ════════════════════════════════════════════════════════════════════════════

class _EduItem {
  String? id;
  String school;
  String degree;
  String fieldOfStudy;
  DateTime? start;
  DateTime? end;
  String grade;
  String description;
  String? locationId;
  String locationLabel;
  Color accent;
  final String? seededSubtitle;
  final String? seededMeta;

  _EduItem({
    this.id,
    required this.school,
    this.degree = '',
    this.fieldOfStudy = '',
    this.start,
    this.end,
    this.grade = '',
    this.description = '',
    this.locationId,
    this.locationLabel = '',
    this.accent = const Color(0xFFC7D2FE),
    this.seededSubtitle,
    this.seededMeta,
  });

  factory _EduItem.fromEntry(ProfileEntry e) => _EduItem(
        id: e.id,
        school: e.title,
        degree: e.degreeName ?? '',
        fieldOfStudy: e.fieldOfStudyName ?? '',
        start: e.startDate,
        end: e.endDate,
        grade: e.grade ?? e.trailingBadge ?? '',
        description: e.description ?? '',
        locationId: e.locationId,
        locationLabel: e.locationLabel ?? '',
        accent:
            profileAccentFromHex(e.accentColorHex) ?? kSaturatedAccents.first,
        seededSubtitle: e.subtitle,
        seededMeta: e.meta,
      );

  String get subtitleLine {
    final composed =
        [degree, fieldOfStudy].where((s) => s.isNotEmpty).join(' · ');
    return composed.isNotEmpty ? composed : (seededSubtitle ?? '');
  }

  String get yearsLine {
    if (start != null || end != null) {
      return [
        if (start != null) '${start!.year}',
        if (end != null) '${end!.year}',
      ].join('–');
    }
    return seededMeta ?? '';
  }

  EducationInput toInput() => EducationInput(
        school: school,
        degreeName: degree,
        fieldOfStudyName: fieldOfStudy,
        startDate: start,
        endDate: end,
        grade: grade,
        description: description,
        accentColorHex: _colorToHex(accent),
        locationId: locationId,
      );
}

class _EducationListSheet extends ConsumerStatefulWidget {
  const _EducationListSheet({required this.seed});

  final List<ProfileEntry> seed;

  @override
  ConsumerState<_EducationListSheet> createState() =>
      _EducationListSheetState();
}

class _EducationListSheetState extends ConsumerState<_EducationListSheet> {
  late final List<_EduItem> _items =
      widget.seed.map(_EduItem.fromEntry).toList();
  int? _deletingIndex;

  Future<void> _openForm({int? index}) async {
    final result = await showProfileSheet<_EduItem>(
      context,
      fullHeight: true,
      builder: (_) =>
          _EducationFormSheet(initial: index == null ? null : _items[index]),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _items.add(result);
      } else {
        _items[index] = result;
      }
    });
  }

  Future<void> _delete(int index) async {
    final item = _items[index];
    if (item.id == null) {
      setState(() => _items.removeAt(index));
      return;
    }
    setState(() => _deletingIndex = index);
    try {
      await ref
          .read(resumeSectionsRepositoryProvider)
          .deleteEducation(item.id!);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      setState(() {
        _items.removeAt(index);
        _deletingIndex = null;
      });
      context.showSnackBar('Education removed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingIndex = null);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _deletingIndex != null;
    return ProfileSheetScaffold(
      title: 'Education',
      icon: Icons.school_outlined,
      tintedIcon: true,
      doneLabel: 'Done',
      onDone: busy ? null : () => Navigator.of(context).pop(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EduCard(
                item: _items[i],
                onEdit: busy ? () {} : () => _openForm(index: i),
                onDelete: busy ? () {} : () => _delete(i),
              ),
            ),
          const SizedBox(height: 2),
          SheetOutlinedAddButton(
            label: 'Add Education',
            onTap: busy ? null : () => _openForm(),
          ),
        ],
      ),
    );
  }
}

class _EduCard extends StatelessWidget {
  const _EduCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final _EduItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final years = item.yearsLine;
    // Same accent derivation as the outer profile EducationCard, so a saved
    // colour renders identically here.
    final tints = educationAccentTints(
      item.accent,
      brightness: Theme.of(context).brightness,
    );
    // The raised tier, like every row in a profile sheet; the saved accent
    // stays on the glyph tile and grade badge, as on the profile itself.
    return ProfileSurface(
      tier: ProfileSurfaceTier.raised,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tints.icon,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.school_outlined, size: 18, color: tints.fg),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.school,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                if (item.subtitleLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitleLine,
                    style:
                        TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (years.isNotEmpty)
                      Text(years,
                          style: TextStyle(
                              fontSize: 11, color: tokens.textTertiary)),
                    if (years.isNotEmpty && item.grade.isNotEmpty)
                      const SizedBox(width: 8),
                    if (item.grade.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tints.icon,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item.grade,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: tints.fg,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SheetRowActions(vertical: true, onEdit: onEdit, onDelete: onDelete),
        ],
      ),
    );
  }
}

class _EducationFormSheet extends ConsumerStatefulWidget {
  const _EducationFormSheet({this.initial});

  final _EduItem? initial;

  @override
  ConsumerState<_EducationFormSheet> createState() =>
      _EducationFormSheetState();
}

class _EducationFormSheetState extends ConsumerState<_EducationFormSheet> {
  late final TextEditingController _school =
      TextEditingController(text: widget.initial?.school ?? '');
  late final TextEditingController _degree =
      TextEditingController(text: widget.initial?.degree ?? '');
  late final TextEditingController _field =
      TextEditingController(text: widget.initial?.fieldOfStudy ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.initial?.description ?? '');

  late DateTime? _start = widget.initial?.start;
  late DateTime? _end = widget.initial?.end;
  late String? _grade = (widget.initial?.grade.isNotEmpty == true &&
          _kGrades.contains(widget.initial!.grade))
      ? widget.initial!.grade
      : null;
  late Color _accent = widget.initial?.accent ?? kSaturatedAccents.first;
  late String? _locationId = widget.initial?.locationId;
  late String _locationLabel = widget.initial?.locationLabel ?? '';
  bool _saving = false;

  // Inline per-field validation state; cleared as soon as the field changes.
  String? _schoolError;
  String? _endError;

  @override
  void dispose() {
    _school.dispose();
    _degree.dispose();
    _field.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final loc = await showLocationPicker(context);
    if (loc != null && mounted) {
      setState(() {
        _locationId = loc.id;
        _locationLabel = loc.label;
      });
    }
  }

  Future<void> _pickStart() async {
    final picked = await showMonthYearPicker(context,
        initial: _start, title: 'Start date');
    if (picked != null) {
      setState(() {
        _start = picked;
        _endError = null;
      });
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showMonthYearPicker(context,
        initial: _end ?? _start, title: 'End date');
    if (picked != null) {
      setState(() {
        _end = picked;
        _endError = null;
      });
    }
  }

  /// Validates the form inline. Returns true when it may be submitted.
  bool _validate() {
    final schoolError = FormValidators.requiredField(_school.text) == null
        ? null
        : 'Add a school or university to continue.';
    String? endError;
    if (_start != null && _end != null && _end!.isBefore(_start!)) {
      endError = "End date can't be before the start date.";
    }
    setState(() {
      _schoolError = schoolError;
      _endError = endError;
    });
    return schoolError == null && endError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final item = _EduItem(
      id: widget.initial?.id,
      school: _school.text.trim(),
      degree: _degree.text.trim(),
      fieldOfStudy: _field.text.trim(),
      start: _start,
      end: _end,
      grade: _grade ?? '',
      description: _description.text.trim(),
      locationId: _locationId,
      locationLabel: _locationLabel,
      accent: _accent,
    );

    final repo = ref.read(resumeSectionsRepositoryProvider);
    setState(() => _saving = true);
    try {
      if (item.id == null) {
        item.id = await repo.createEducation(item.toInput());
      } else {
        await repo.updateEducation(item.id!, item.toInput());
      }
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.showSnackBar(
          widget.initial == null ? 'Education added' : 'Education saved');
      Navigator.of(context).pop(item);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return ProfileSheetScaffold(
      title: 'Education',
      icon: Icons.school_outlined,
      fullHeight: true,
      showBack: true,
      footer: SheetPrimaryButton(
        label: _saving
            ? 'Saving…'
            : (editing ? 'Save Education' : 'Add Education'),
        onTap: _saving ? null : _submit,
        loading: _saving,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTextField(
            label: 'School / University',
            hint: 'e.g. MIT, Oxford',
            controller: _school,
            errorText: _schoolError,
            onChanged: (_) {
              if (_schoolError != null) setState(() => _schoolError = null);
            },
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Degree',
            hint: 'e.g. Bachelor of Science',
            controller: _degree,
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Field Of Study',
            hint: 'e.g. Computer Science',
            controller: _field,
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SheetDateField(
                  label: 'Start',
                  hint: 'Select month',
                  value: formatMonthYear(_start),
                  onTap: _pickStart,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SheetDateField(
                  label: 'End',
                  hint: 'Select month',
                  value: formatMonthYear(_end),
                  onTap: _pickEnd,
                  errorText: _endError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Grade', style: _formLabelStyle(context)),
          const SizedBox(height: 10),
          SheetChipGroup(
            options: _kGrades,
            selected: _grade,
            onSelected: (v) => setState(() => _grade = _grade == v ? null : v),
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Description',
            hint: 'Activities, achievements, focus areas…',
            controller: _description,
            maxLines: 3,
            maxLength: 300,
            showCounter: true,
          ),
          const SizedBox(height: 18),
          SheetTapField(
            label: 'Location',
            hint: 'Search a city',
            value: _locationLabel,
            trailingIcon: Icons.search,
            onTap: _pickLocation,
            onClear: () => setState(() {
              _locationId = null;
              _locationLabel = '';
            }),
          ),
          const SizedBox(height: 18),
          AccentColorPicker(
            palette: kSaturatedAccents,
            selected: _accent,
            onSelected: (c) => setState(() => _accent = c),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Skills
// ════════════════════════════════════════════════════════════════════════════

class _SkillFormResult {
  /// New skills to add to [category].
  final List<String> added;

  /// Existing skills the user removed inside the form.
  final List<String> removed;
  final String category;

  /// Chosen category accent colour (null = left unchanged).
  final Color? color;

  const _SkillFormResult(this.added, this.removed, this.category, this.color);
}

class _SkillsSheet extends ConsumerStatefulWidget {
  const _SkillsSheet({required this.seed, required this.seedColors});

  final Map<String, List<String>> seed;
  final Map<String, String> seedColors;

  @override
  ConsumerState<_SkillsSheet> createState() => _SkillsSheetState();
}

class _SkillsSheetState extends ConsumerState<_SkillsSheet> {
  // Preserve insertion order; mutable working copy of the categorized skills.
  late final Map<String, List<String>> _groups = {
    for (final e in widget.seed.entries) e.key: List<String>.from(e.value),
  };

  // Normalized snapshot of the skills present when the sheet opened — used to
  // diff on commit so we only create/delete what actually changed.
  late final Set<String> _seedNames = {
    for (final list in widget.seed.values)
      for (final s in list) s.trim().toLowerCase(),
  };

  // Category → hex accent, keyed uppercase. `_seedColors` is the baseline;
  // `_colors` is the working copy so we can diff on commit and persist only the
  // categories whose colour actually changed.
  late final Map<String, String> _seedColors = {
    for (final e in widget.seedColors.entries) e.key.toUpperCase(): e.value,
  };
  late final Map<String, String> _colors =
      Map<String, String>.from(_seedColors);

  bool _saving = false;

  /// The category's saved colour, or null for the neutral treatment.
  Color? _colorFor(String category) => skillCategoryColor(category, _colors);

  /// Persists the delta on Done: skill adds/deletes (create-batch / delete-batch)
  /// and any changed category colours (`profile-theme`). Nothing changed → close.
  Future<void> _commit() async {
    final added = <SkillInput>[];
    final finalNames = <String>{};
    for (final entry in _groups.entries) {
      for (final name in entry.value) {
        final norm = name.trim().toLowerCase();
        finalNames.add(norm);
        if (!_seedNames.contains(norm)) {
          added.add(SkillInput(name, entry.key));
        }
      }
    }
    final removed = <String>[
      for (final list in widget.seed.values)
        for (final s in list)
          if (!finalNames.contains(s.trim().toLowerCase())) s,
    ];

    // Colour delta: categories whose hex differs from the seed.
    final changedColors = <String, String>{};
    for (final entry in _colors.entries) {
      if (_seedColors[entry.key] != entry.value) {
        changedColors[entry.key] = entry.value;
      }
    }

    if (added.isEmpty && removed.isEmpty && changedColors.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final repo = ref.read(resumeSectionsRepositoryProvider);
    setState(() => _saving = true);
    try {
      await repo.deleteSkills(removed);
      await repo.addSkills(added);
      // Send the full colour map (not just the delta) so replace-semantics on
      // the theme endpoint can't drop other categories' saved colours.
      if (changedColors.isNotEmpty) {
        await repo.updateSkillCategoryColors(_colors);
      }
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.showSnackBar('Skills updated');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  List<String> get _categoryOptions {
    final existing = _groups.keys
        .map((k) => k[0].toUpperCase() + k.substring(1).toLowerCase())
        .toList();
    for (final c in _kDefaultSkillCategories) {
      if (!existing.any((e) => e.toUpperCase() == c.toUpperCase())) {
        existing.add(c);
      }
    }
    return existing;
  }

  Future<void> _openForm({String? presetCategory}) async {
    final result = await showProfileSheet<_SkillFormResult>(
      context,
      fullHeight: true,
      builder: (_) => _SkillFormSheet(
        categories: _categoryOptions,
        presetCategory: presetCategory,
        // Give the form the current working set so it can show a category's
        // existing skills (removable) alongside adding new ones.
        existingGroups: {
          for (final e in _groups.entries) e.key: List<String>.from(e.value),
        },
        initialColor: presetCategory == null ? null : _colorFor(presetCategory),
      ),
    );
    if (result == null || !mounted) return;
    if (result.added.isEmpty &&
        result.removed.isEmpty &&
        result.color == null) {
      return;
    }
    setState(() {
      // Match an existing category case-insensitively, else create it.
      final key = _groups.keys.firstWhere(
        (k) => k.toUpperCase() == result.category.toUpperCase(),
        orElse: () => result.category.toUpperCase(),
      );
      final list = _groups.putIfAbsent(key, () => <String>[]);
      // Removals first, then additions.
      for (final r in result.removed) {
        list.removeWhere((s) => s.toLowerCase() == r.toLowerCase());
      }
      for (final name in result.added) {
        if (!list.any((s) => s.toLowerCase() == name.toLowerCase())) {
          list.add(name);
        }
      }
      if (list.isEmpty) _groups.remove(key);
      if (result.color != null) {
        _colors[key.toUpperCase()] = _colorToHex(result.color!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final entries = _groups.entries.toList();
    return ProfileSheetScaffold(
      title: 'Skills',
      icon: Icons.star_border,
      tintedIcon: true,
      doneLabel: _saving ? 'Saving…' : 'Done',
      onDone: _saving ? null : _commit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            _SkillCategoryEditor(
              title: entries[i].key,
              values: entries[i].value,
              color: _colorFor(entries[i].key),
              onAdd: () => _openForm(presetCategory: entries[i].key),
              onRemove: (skill) => setState(() {
                entries[i].value.remove(skill);
                if (entries[i].value.isEmpty) _groups.remove(entries[i].key);
              }),
            ),
          ],
          if (entries.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No skills yet. Add your first below.',
                style: TextStyle(fontSize: 13, color: tokens.textTertiary),
              ),
            ),
          const SizedBox(height: 18),
          SheetOutlinedAddButton(
            label: 'Add Skills',
            onTap: () => _openForm(),
          ),
        ],
      ),
    );
  }
}

class _SkillCategoryEditor extends StatelessWidget {
  const _SkillCategoryEditor({
    required this.title,
    required this.values,
    required this.color,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<String> values;

  /// The category's saved accent, or null for the neutral treatment — the
  /// same rule as `SkillCategoryBlock` on the profile.
  final Color? color;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: color ?? colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onAdd,
              child: Icon(Icons.edit_outlined,
                  size: 14, color: color ?? tokens.controlInk),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              SheetRemovableChip(
                label: value,
                color: color ?? colors.outline,
                onRemove: () => onRemove(value),
              ),
          ],
        ),
      ],
    );
  }
}

class _SkillFormSheet extends ConsumerStatefulWidget {
  const _SkillFormSheet({
    required this.categories,
    required this.existingGroups,
    this.presetCategory,
    this.initialColor,
  });

  final List<String> categories;
  final Map<String, List<String>> existingGroups;
  final String? presetCategory;
  final Color? initialColor;

  @override
  ConsumerState<_SkillFormSheet> createState() => _SkillFormSheetState();
}

class _SkillFormSheetState extends ConsumerState<_SkillFormSheet> {
  final TextEditingController _name = TextEditingController();
  late final TextEditingController _categoryCtrl =
      TextEditingController(text: _resolvePreset());
  final List<String> _names = [];

  /// Existing skills (from the selected category) the user removed here.
  final Set<String> _removed = {};
  late String _category = _resolvePreset();

  /// Backend category suggestions for the current query (`/skill/categories`).
  List<String> _suggestions = const [];

  /// Chosen category accent — persisted to the backend on Done as the whole
  /// category's colour (the backend keys accent colours by category, not skill).
  late Color _accent = widget.initialColor ?? kSaturatedAccents.first;
  bool _colorTouched = false;

  /// Existing skills of the currently-selected category, minus what's removed.
  List<String> get _existingInCategory {
    final key = widget.existingGroups.keys.firstWhere(
      (k) => k.toUpperCase() == _category.trim().toUpperCase(),
      orElse: () => '',
    );
    if (key.isEmpty) return const [];
    return widget.existingGroups[key]!
        .where((s) => !_removed.contains(s.toLowerCase()))
        .toList(growable: false);
  }

  /// Curated skill-name suggestions for the current name query (local source).
  List<String> get _nameSuggestions {
    final q = _name.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _kCommonSkills
        .where((s) =>
            s.toLowerCase().contains(q) &&
            !_names.any((n) => n.toLowerCase() == s.toLowerCase()))
        .take(6)
        .toList(growable: false);
  }

  String _resolvePreset() {
    if (widget.presetCategory != null) {
      final match = widget.categories.firstWhere(
        (c) => c.toUpperCase() == widget.presetCategory!.toUpperCase(),
        orElse: () =>
            widget.categories.isNotEmpty ? widget.categories.first : 'General',
      );
      return match;
    }
    return widget.categories.isNotEmpty ? widget.categories.first : 'General';
  }

  @override
  void dispose() {
    _name.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _addChip([String? raw]) {
    final value = (raw ?? _name.text).trim();
    if (value.isEmpty) return;
    if (!_names.any((s) => s.toLowerCase() == value.toLowerCase())) {
      setState(() => _names.add(value));
    }
    _name.clear();
  }

  /// Query the backend for matching categories as the user types. There's no
  /// "list all categories" endpoint, so this autocomplete (max 5) plus the
  /// free-text field is the real category source; chips below are quick picks.
  Future<void> _onCategoryChanged(String value) async {
    final q = value.trim();
    setState(() => _category = q);
    if (q.isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    final res = await ref
        .read(resumeSectionsRepositoryProvider)
        .searchSkillCategories(q);
    if (!mounted) return;
    setState(() => _suggestions = res);
  }

  void _pickCategory(String value) {
    setState(() {
      _category = value;
      _categoryCtrl.text = value;
      _suggestions = const [];
    });
  }

  void _submit() {
    _addChip();
    final category = _category.trim().isEmpty ? 'General' : _category.trim();
    if (_names.isEmpty && _removed.isEmpty && !_colorTouched) {
      _honestToast(context, 'Add a skill or make a change to continue.');
      return;
    }
    // Map removed-lowercase back to the original casing for the delete call.
    final key = widget.existingGroups.keys.firstWhere(
      (k) => k.toUpperCase() == category.toUpperCase(),
      orElse: () => '',
    );
    final removedOriginal = <String>[
      if (key.isNotEmpty)
        for (final s in widget.existingGroups[key]!)
          if (_removed.contains(s.toLowerCase())) s,
    ];
    Navigator.of(context).pop(
      _SkillFormResult(
        List.of(_names),
        removedOriginal,
        category,
        _colorTouched ? _accent : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Quick-pick chips = the user's existing categories + any live suggestions,
    // de-duped case-insensitively.
    final quickPicks = <String>[];
    for (final c in [...widget.categories, ..._suggestions]) {
      if (!quickPicks.any((e) => e.toUpperCase() == c.toUpperCase())) {
        quickPicks.add(c);
      }
    }
    final selectedChip = quickPicks.firstWhere(
      (c) => c.toUpperCase() == _category.toUpperCase(),
      orElse: () => '',
    );
    final existing = _existingInCategory;

    return ProfileSheetScaffold(
      title: 'Skills',
      icon: Icons.star_border,
      fullHeight: true,
      showBack: true,
      footer: SheetPrimaryButton(label: 'Save Skills', onTap: _submit),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTextField(
            label: 'Skill Name',
            hint: 'e.g. Figma, User Research',
            controller: _name,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.secondary(
              label: 'Add',
              leading: Icons.add,
              semanticLabel: 'Add skill',
              onPressed: () => _addChip(),
              expand: false,
              size: AppButtonSize.compact,
            ),
          ),
          // Suggestions (local) — tap to add.
          if (_nameSuggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            const SheetSectionLabel('Suggestions'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _nameSuggestions)
                  AppChip(
                    label: s,
                    variant: AppChipVariant.filter,
                    icon: Icons.add,
                    semanticLabel: 'Add $s',
                    onTap: () => _addChip(s),
                  ),
              ],
            ),
          ],
          // Newly-added (this session) chips.
          if (_names.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _names)
                  SheetRemovableChip(
                    label: name,
                    color: context.colorScheme.outline,
                    onRemove: () => setState(() => _names.remove(name)),
                  ),
              ],
            ),
          ],
          // Existing skills already in the selected category — removable here.
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 18),
            SheetSectionLabel('Already in ${_category.trim()}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final skill in existing)
                  SheetRemovableChip(
                    label: skill,
                    color: _accent,
                    onRemove: () =>
                        setState(() => _removed.add(skill.toLowerCase())),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Category',
            hint: 'Search or type a category',
            controller: _categoryCtrl,
            onChanged: _onCategoryChanged,
          ),
          const SizedBox(height: 12),
          if (quickPicks.isNotEmpty)
            SheetChipGroup(
              options: quickPicks,
              selected: selectedChip.isEmpty ? null : selectedChip,
              onSelected: _pickCategory,
            ),
          const SizedBox(height: 18),
          AccentColorPicker(
            palette: kSaturatedAccents,
            selected: _accent,
            onSelected: (c) => setState(() {
              _accent = c;
              _colorTouched = true;
            }),
          ),
          const SizedBox(height: 10),
          const SheetSyncNote(
            message:
                'Colour applies to the whole category and is saved to your profile.',
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Languages
// ════════════════════════════════════════════════════════════════════════════

class _LangItem {
  String name;
  String level;
  double progress;

  _LangItem({required this.name, required this.level, required this.progress});

  factory _LangItem.fromEntry(LanguageEntry l) => _LangItem(
        name: l.name,
        level: l.level,
        progress: l.progress > 0 ? l.progress : _proficiencyProgress(l.level),
      );
}

class _LanguagesListSheet extends ConsumerStatefulWidget {
  const _LanguagesListSheet({required this.seed});

  final List<LanguageEntry> seed;

  @override
  ConsumerState<_LanguagesListSheet> createState() =>
      _LanguagesListSheetState();
}

class _LanguagesListSheetState extends ConsumerState<_LanguagesListSheet> {
  late final List<_LangItem> _items =
      widget.seed.map(_LangItem.fromEntry).toList();

  bool _saving = false;

  /// The languages endpoint is a whole-list replace, so commit sends the
  /// current working set (adds, edits and deletes already folded in), then
  /// invalidates the profile so the change shows live and closes the sheet.
  Future<void> _commit() async {
    final repo = ref.read(resumeSectionsRepositoryProvider);
    setState(() => _saving = true);
    try {
      await repo.replaceLanguages([
        for (final it in _items)
          LanguageInput(it.name, _normalizeProficiency(it.level)),
      ]);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.showSnackBar('Languages updated');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _openForm({int? index}) async {
    final result = await showProfileSheet<_LangItem>(
      context,
      builder: (_) =>
          _LanguageFormSheet(initial: index == null ? null : _items[index]),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _items.add(result);
      } else {
        _items[index] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProfileSheetScaffold(
      title: 'Languages',
      icon: Icons.language,
      tintedIcon: true,
      doneLabel: _saving ? 'Saving…' : 'Done',
      onDone: _saving ? null : _commit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _LangRow(
                item: _items[i],
                onEdit: () => _openForm(index: i),
                onDelete: () => setState(() => _items.removeAt(i)),
              ),
            ),
          const SizedBox(height: 2),
          SheetOutlinedAddButton(
            label: 'Add Language',
            onTap: () => _openForm(),
          ),
        ],
      ),
    );
  }
}

class _LangRow extends StatelessWidget {
  const _LangRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final _LangItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    item.level,
                    style:
                        TextStyle(fontSize: 11.5, color: tokens.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: item.progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: ProfileSurfaceTokens.of(context).raisedFill,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      context.tokensOrDefault.controlInk),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SheetRowActions(onEdit: onEdit, onDelete: onDelete),
      ],
    );
  }
}

class _LanguageFormSheet extends StatefulWidget {
  const _LanguageFormSheet({this.initial});

  final _LangItem? initial;

  @override
  State<_LanguageFormSheet> createState() => _LanguageFormSheetState();
}

class _LanguageFormSheetState extends State<_LanguageFormSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late String _level = (widget.initial?.level != null &&
          _kProficiencyLevels.contains(widget.initial!.level))
      ? widget.initial!.level
      : _kProficiencyLevels.first;

  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Add a language to continue.');
      return;
    }
    Navigator.of(context).pop(
      _LangItem(
        name: _name.text.trim(),
        level: _level,
        progress: _proficiencyProgress(_level),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return ProfileSheetScaffold(
      title: 'Languages',
      icon: Icons.language,
      showBack: true,
      footer: SheetPrimaryButton(
        label: editing ? 'Save Language' : 'Add Language',
        onTap: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTextField(
            label: 'Language',
            hint: 'e.g. English, Kannada…',
            controller: _name,
            errorText: _nameError,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 18),
          Text('Proficiency Level', style: _formLabelStyle(context)),
          const SizedBox(height: 10),
          SheetChipGroup(
            options: _kProficiencyLevels,
            selected: _level,
            onSelected: (v) => setState(() => _level = v),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Social Links
// ════════════════════════════════════════════════════════════════════════════

/// Work & portfolio links editor.
///
/// Uses the same [WorkLinksEditor] as onboarding — paste any URL, the platform
/// is detected from the domain — so the two surfaces cannot drift, and so a
/// designer/creator can add Figma, Dribbble, Behance, Medium, Substack,
/// YouTube or their own site, none of which have a dedicated backend column.
///
/// Saving diffs the edited list against the profile's stored columns via
/// [workLinksToProfileLinksPayload]: untouched columns are omitted (partial
/// update), and a column is cleared only when it genuinely held a link the user
/// removed.
class _SocialLinksSheet extends ConsumerStatefulWidget {
  const _SocialLinksSheet({required this.seed});

  final ProfileLinks seed;

  @override
  ConsumerState<_SocialLinksSheet> createState() => _SocialLinksSheetState();
}

class _SocialLinksSheetState extends ConsumerState<_SocialLinksSheet> {
  final _editorKey = GlobalKey<WorkLinksEditorState>();
  late List<WorkLink> _links = widget.seed.resolved;
  bool _saving = false;

  Future<void> _commit() async {
    // A link typed but not yet added counts as intent to add.
    if (!(_editorKey.currentState?.commitPending() ?? true)) return;

    final changed = workLinksToProfileLinksPayload(
      _links,
      previous: widget.seed.columns,
    );

    if (changed.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(resumeSectionsRepositoryProvider)
          .updateProfileLinks(changed);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.showSnackBar('Links updated');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProfileSheetScaffold(
      title: 'Work & Social Links',
      icon: Icons.link,
      tintedIcon: false,
      fullHeight: true,
      subtitle: 'Add links so people can connect with you outside SyncUp',
      footer: SheetPrimaryButton(
        label: _saving ? 'Saving…' : 'Save Links',
        onTap: _saving ? null : _commit,
        loading: _saving,
      ),
      body: WorkLinksEditor(
        key: _editorKey,
        links: _links,
        enabled: !_saving,
        onChanged: (next) => setState(() => _links = next),
        emptyHint: 'Paste a link above to show it on your profile.',
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Edit Cover
// ════════════════════════════════════════════════════════════════════════════

/// Solid cover colours. The backend supports a solid `profileBannerColor` only
/// (no gradient), so these are honest single-colour presets.
List<Color> _kCoverColors = [
  Color(0xFF6366F1), // indigo
  Color(0xFF0EA5E9), // sky
  Color(0xFF10B981), // emerald
  Color(0xFFF59E0B), // amber
  Color(0xFFEC4899), // pink
  Color(0xFF1E1B4B), // midnight
  Color(0xFF14B8A6), // teal
  Color(0xFFFB923C), // peach
  Color(0xFF111827), // near-black
];
// The swatch list above is **user-chosen content** — a saved cover colour is
// part of the profile, so it renders identically in both themes. Same reason
// `profile_edit_sheets.dart` stays on the allowlist.

/// Edit Cover — persists a **solid** banner colour (`profile-theme`) or uploads
/// a banner **photo** (auth-service presigned flow). Both refresh the profile.
class _EditCoverSheet extends ConsumerStatefulWidget {
  const _EditCoverSheet();

  @override
  ConsumerState<_EditCoverSheet> createState() => _EditCoverSheetState();
}

class _EditCoverSheetState extends ConsumerState<_EditCoverSheet> {
  int _tab = 0; // 0 = Color, 1 = Photo
  int _color = 0;
  bool _busy = false;

  Future<void> _applyColor() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(resumeSectionsRepositoryProvider)
          .updateProfileBannerColor(_colorToHex(_kCoverColors[_color]));
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.showSnackBar('Cover updated');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _pickBannerPhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _pickAndUploadImage(ref, isBanner: true);
    if (!mounted) return;
    if (ok == null) {
      setState(() => _busy = false); // cancelled
      return;
    }
    if (ok) {
      context.showSnackBar('Cover photo updated');
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
      context
          .showErrorSnackBar("Couldn't update your cover. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final selected = _kCoverColors[_color];
    return ProfileSheetScaffold(
      title: 'Edit Cover',
      subtitle: 'Customize your profile cover',
      footer: _tab == 0
          ? SheetPrimaryButton(
              label: _busy ? 'Saving…' : 'Apply Cover',
              onTap: _busy ? null : _applyColor,
              loading: _busy,
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live preview banner.
          ClipRRect(
            borderRadius:
                BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
            child: Container(
              height: 96,
              width: double.infinity,
              decoration: _tab == 0
                  ? BoxDecoration(color: selected)
                  : BoxDecoration(
                      color: ProfileSurfaceTokens.of(context).insetFill),
              child: _tab == 1
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_outlined,
                              size: 26, color: tokens.textTertiary),
                          SizedBox(height: 6),
                          Text(
                            'Upload a cover photo below',
                            style: TextStyle(
                                fontSize: 12.5, color: tokens.textTertiary),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          AppSegmented<int>(
            padding: EdgeInsets.zero,
            selected: _tab,
            onChanged: _busy ? (_) {} : (i) => setState(() => _tab = i),
            segments: const [
              AppSegment(
                  value: 0, label: 'Color', icon: Icons.palette_outlined),
              AppSegment(value: 1, label: 'Photo', icon: Icons.image_outlined),
            ],
          ),
          const SizedBox(height: 18),
          if (_tab == 0) ...[
            const SheetSectionLabel('Choose a colour'),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _kCoverColors.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.5,
              ),
              itemBuilder: (context, i) => _ColorTile(
                color: _kCoverColors[i],
                selected: i == _color,
                onTap: () => setState(() => _color = i),
              ),
            ),
          ] else ...[
            _PhotoUploadZone(busy: _busy, onTap: _pickBannerPhoto),
          ],
        ],
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({
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
    // The swatch is the user's own colour in both themes, so its check takes
    // whichever fixed media ink reads on it.
    final checkInk = color.computeLuminance() > 0.45
        ? tokens.mediaSurface
        : tokens.onMediaSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Cover colour',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: AppMotion.durationFor(context, AppMotion.state),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
                color: color,
                // The page's high-emphasis ink, so the choice reads on the
                // charcoal sheet whatever the swatch is.
                border: selected
                    ? Border.all(color: colors.onSurface, width: 2)
                    : null,
              ),
            ),
            if (selected)
              Positioned(
                right: 6,
                top: 6,
                child: Icon(Icons.check_circle, size: 16, color: checkInk),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Upload from device": the app's secondary button, full width.
class _PhotoUploadZone extends StatelessWidget {
  const _PhotoUploadZone({required this.onTap, this.busy = false});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppButton.secondary(
      label: 'Upload from device',
      leading: Icons.upload_outlined,
      loading: busy,
      onPressed: onTap,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Projects (Add / Edit)
// ════════════════════════════════════════════════════════════════════════════

class _ProjectFormSheet extends ConsumerStatefulWidget {
  const _ProjectFormSheet({this.initial});

  final ProjectEntry? initial;

  @override
  ConsumerState<_ProjectFormSheet> createState() => _ProjectFormSheetState();
}

class _ProjectFormSheetState extends ConsumerState<_ProjectFormSheet> {
  static const int _minProjectYear = 1950;

  late final TextEditingController _title =
      TextEditingController(text: widget.initial?.title ?? '');
  late final TextEditingController _year = TextEditingController(
      text: widget.initial?.startDate?.year.toString() ?? '');

  /// The stored description carries the website's `[Personal]` / `[Freelance]`
  /// marker, so it is split into the association choice and the prose body the
  /// user actually typed.
  late final ({ProjectAssociation association, String description}) _seeded =
      ProjectInput.readAssociation(
    widget.initial?.description,
    experienceId: widget.initial?.experienceId,
  );

  late final TextEditingController _description =
      TextEditingController(text: _seeded.description);
  late final TextEditingController _link =
      TextEditingController(text: widget.initial?.linkUrl ?? '');

  /// Extra links, edited as rows. Seeded from the record so a mobile save
  /// never drops links added on the website.
  late final List<TextEditingController> _extraLinks = [
    for (final url in widget.initial?.additionalLinks ?? const <String>[])
      TextEditingController(text: url),
  ];

  late ProjectAssociation _association = _seeded.association;
  late String? _experienceId = widget.initial?.experienceId;
  late DateTime? _endDate = widget.initial?.endDate;
  late bool _currentlyWorking = widget.initial?.currentlyWorking ?? false;

  /// Cover state: an existing (already-saved) cover URL/keys, a freshly picked
  /// local file to upload, or removed. The submit reconciles these.
  late final String? _existingCoverUrl = widget.initial?.coverUrl;
  late List<String> _existingKeys =
      List<String>.from(widget.initial?.attachmentKeys ?? const []);
  File? _newCover;
  bool _coverRemoved = false;
  bool _saving = false;

  // Inline per-field validation state; cleared as soon as the field changes.
  String? _titleError;
  String? _yearError;
  String? _descriptionError;
  String? _linkError;
  String? _coverError;
  String? _extraLinksError;
  String? _associationError;

  bool get _editing => widget.initial != null;

  bool get _hasCover =>
      _newCover != null || (!_coverRemoved && _existingKeys.isNotEmpty);

  /// Validates the whole form, surfacing every problem inline at once.
  /// Returns true when the form may be submitted.
  bool _validate() {
    final titleError = FormValidators.requiredField(_title.text) == null
        ? null
        : 'Add a title to continue.';
    final yearError = FormValidators.optionalYear(_year.text);
    final descriptionError =
        FormValidators.projectDescription(_description.text);
    final linkError = FormValidators.webAddress(_link.text);
    final coverError = _hasCover ? null : 'Add a cover image to continue.';

    String? extraLinksError;
    final filled = [
      for (final c in _extraLinks)
        if (c.text.trim().isNotEmpty) c.text,
    ];
    if (filled.length > ProjectInput.maxAdditionalLinks) {
      extraLinksError =
          'Add up to ${ProjectInput.maxAdditionalLinks} extra links.';
    } else {
      for (final url in filled) {
        final problem = FormValidators.webAddress(url);
        if (problem != null) {
          extraLinksError = problem;
          break;
        }
      }
    }

    // "Associated with" is required on the website too. When Experience is
    // chosen there has to be a real record behind it — the backend takes a
    // UUID, not a label.
    final associationError = _association == ProjectAssociation.experience &&
            (_experienceId ?? '').isEmpty
        ? 'Choose what this work belongs to.'
        : null;

    setState(() {
      _titleError = titleError;
      _yearError = yearError;
      _descriptionError = descriptionError;
      _linkError = linkError;
      _coverError = coverError;
      _extraLinksError = extraLinksError;
      _associationError = associationError;
    });
    return titleError == null &&
        yearError == null &&
        descriptionError == null &&
        linkError == null &&
        coverError == null &&
        extraLinksError == null &&
        associationError == null;
  }

  @override
  void dispose() {
    _title.dispose();
    _year.dispose();
    _description.dispose();
    _link.dispose();
    for (final c in _extraLinks) {
      c.dispose();
    }
    super.dispose();
  }

  /// Non-empty extra links, normalised to absolute URLs. The schema validates
  /// each with `new URL(...)`, so a bare host is a 400.
  List<String> get _normalizedExtraLinks => [
        for (final c in _extraLinks)
          if (c.text.trim().isNotEmpty) FormValidators.normalizeUrl(c.text),
      ];

  Future<void> _pickCover() async {
    final picked = await _pickImageFile();
    if (picked != null && mounted) {
      setState(() {
        _newCover = picked;
        _coverRemoved = false;
        _coverError = null;
      });
    }
  }

  Future<void> _pickProjectYear(BuildContext context) async {
    final colors = context.colorScheme;
    final now = DateTime.now().year;
    final maxYear = now + 1;
    final selectedYear = int.tryParse(_year.text.trim()) ??
        widget.initial?.startDate?.year ??
        now;
    final picked = await showDialog<int>(
      context: context,
      // Pane, shape and rim come from `DialogThemeData` — the same overlay
      // glass as every other dialog in the app.
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: SizedBox(
          width: 320,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 6),
                child: Text(
                  'Select year',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                  itemCount: maxYear - _minProjectYear + 1,
                  itemBuilder: (context, index) {
                    final year = maxYear - index;
                    final selected = year == selectedYear;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(dialogContext).pop(year),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: selected
                                ? colors.surfaceContainerHigh
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$year',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(Icons.check,
                                    size: 18,
                                    color: context.tokensOrDefault.controlInk),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 10, 10),
                  child: AppButton.text(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _year.text = '$picked';
      _yearError = null;
    });
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final year = int.tryParse(_year.text.trim());
    final repo = ref.read(projectsRepositoryProvider);
    setState(() => _saving = true);
    try {
      // Resolve the cover attachment: upload a newly picked file, drop the
      // cover if removed, otherwise keep what was already attached. Sent as
      // `{key, mediaType}` pairs — a bare string is coerced to `image`, which
      // would mislabel anything else.
      List<ProjectAttachment> attachments;
      if (_newCover != null) {
        final path = _newCover!.path;
        final key = await repo.uploadCover(
          filePath: path,
          extension: _extensionOf(path),
          contentType: _imageMimeFor(path),
        );
        attachments = [ProjectAttachment(key)];
      } else if (_coverRemoved) {
        attachments = const [];
      } else {
        attachments = [for (final k in _existingKeys) ProjectAttachment(k)];
      }

      // Personal / Freelance are encoded as a description marker with a null
      // experienceId — the website's convention, matched so an entry reads the
      // same on both platforms.
      final resolved = ProjectInput.applyAssociation(
        association: _association,
        experienceId: _experienceId,
        description: _description.text,
      );

      final input = ProjectInput(
        title: _title.text.trim(),
        description: resolved.description,
        attachments: attachments,
        linkUrl: FormValidators.normalizeUrl(_link.text),
        additionalLinks: _normalizedExtraLinks,
        currentlyWorking: _currentlyWorking,
        startDate: year == null ? null : DateTime(year),
        endDate: _endDate,
        experienceId: resolved.experienceId,
        sortOrder: widget.initial?.sortOrder,
      );

      if (_editing && widget.initial!.id != null) {
        await repo.updateProject(widget.initial!.id!, input);
      } else {
        await repo.createProject(input);
      }
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.showSnackBar(
          _editing ? 'Proof of work updated' : 'Proof of work added');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _delete() async {
    final id = widget.initial?.id;
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(projectsRepositoryProvider).deleteProject(id);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.showSnackBar('Project removed');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final coverUrl = _coverRemoved ? null : _existingCoverUrl;
    return ProfileSheetScaffold(
      // Add Proof of Work: back + star + title + close (matches artboard). Edit
      // Project: leading close + title (matches its artboard).
      title: _editing ? 'Edit Proof of Work' : 'Add Proof of Work',
      icon: _editing ? null : Icons.star_border,
      fullHeight: true,
      showBack: !_editing,
      closeOnLeft: _editing,
      footer: _editing
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DeleteProjectButton(onTap: _saving ? () {} : _delete),
                const SizedBox(height: 10),
                SheetPrimaryButton(
                  label: _saving ? 'Saving…' : 'Update Project',
                  onTap: _saving ? null : _submit,
                  loading: _saving,
                ),
              ],
            )
          : SheetPrimaryButton(
              label: _saving ? 'Saving…' : 'Add Proof of Work',
              onTap: _saving ? null : _submit,
              loading: _saving,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProjectCoverZone(
            file: _newCover,
            url: coverUrl,
            onTapCover: _saving ? () {} : _pickCover,
            onRemove: (_newCover != null || coverUrl != null)
                ? () => setState(() {
                      _newCover = null;
                      _coverRemoved = true;
                      _existingKeys = const [];
                    })
                : null,
          ),
          if (_coverError != null) ...[
            const SizedBox(height: 8),
            Text(
              _coverError!,
              style: TextStyle(fontSize: 11.5, color: colors.error),
            ),
          ],
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Project Title',
            hint: 'e.g. SyncUp App Redesign',
            controller: _title,
            errorText: _titleError,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
          ),
          const SizedBox(height: 18),
          SheetDateField(
            label: 'Year',
            hint: 'Select year',
            value: _year.text,
            onTap: _saving ? () {} : () => _pickProjectYear(context),
            errorText: _yearError,
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Description',
            hint: 'What did you achieve here?',
            controller: _description,
            maxLines: 3,
            maxLength: 300,
            showCounter: true,
            errorText: _descriptionError,
            onChanged: (_) {
              if (_descriptionError != null) {
                setState(() => _descriptionError = null);
              }
            },
          ),
          const SizedBox(height: 18),
          SheetTextField(
            label: 'Project Link',
            hint: 'https://',
            controller: _link,
            leadingIcon: Icons.link,
            keyboardType: TextInputType.url,
            errorText: _linkError,
            onChanged: (_) {
              if (_linkError != null) setState(() => _linkError = null);
            },
          ),
          const SizedBox(height: 18),
          _AdditionalLinksEditor(
            controllers: _extraLinks,
            errorText: _extraLinksError,
            onAdd: _extraLinks.length >= ProjectInput.maxAdditionalLinks
                ? null
                : () => setState(() {
                      _extraLinks.add(TextEditingController());
                      _extraLinksError = null;
                    }),
            onRemove: (index) => setState(() {
              _extraLinks.removeAt(index).dispose();
              _extraLinksError = null;
            }),
            onChanged: () {
              if (_extraLinksError != null) {
                setState(() => _extraLinksError = null);
              }
            },
          ),
          const SizedBox(height: 18),
          SheetDateField(
            label: 'End Date',
            hint: 'Select month',
            value: formatMonthYear(_endDate),
            enabled: !_currentlyWorking,
            onTap: _saving
                ? () {}
                : () async {
                    final picked = await showMonthYearPicker(
                      context,
                      initial: _endDate,
                      title: 'End date',
                    );
                    if (picked != null && mounted) {
                      setState(() => _endDate = picked);
                    }
                  },
          ),
          const SizedBox(height: 14),
          SheetCheckboxRow(
            label: 'I am still working on this',
            value: _currentlyWorking,
            onChanged: (v) => setState(() {
              _currentlyWorking = v;
              if (v) _endDate = null;
            }),
          ),
          const SizedBox(height: 18),
          _AssociationPicker(
            association: _association,
            experienceId: _experienceId,
            errorText: _associationError,
            onChanged: (association, experienceId) => setState(() {
              _association = association;
              _experienceId = experienceId;
              _associationError = null;
            }),
          ),
        ],
      ),
    );
  }
}

/// Extra links beyond the primary one — the website's `additionalLinks`,
/// capped at [ProjectInput.maxAdditionalLinks] by the schema.
class _AdditionalLinksEditor extends StatelessWidget {
  const _AdditionalLinksEditor({
    required this.controllers,
    required this.errorText,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  final List<TextEditingController> controllers;
  final String? errorText;

  /// Null once the cap is reached, which disables the add affordance rather
  /// than letting the user type a link the server will reject.
  final VoidCallback? onAdd;
  final void Function(int index) onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Additional Links', style: _formLabelStyle(context)),
        const SizedBox(height: 8),
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: SheetTextField(
                    label: 'Link ${i + 1}',
                    hint: 'https://',
                    controller: controllers[i],
                    leadingIcon: Icons.link,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                IconButton(
                  onPressed: () => onRemove(i),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 16, color: colors.error),
                ),
              ],
            ),
          ),
        if (onAdd != null)
          GestureDetector(
            onTap: onAdd,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(Icons.add,
                    size: 16, color: context.tokensOrDefault.controlInk),
                const SizedBox(width: 5),
                Text(
                  'Add link',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.tokensOrDefault.controlInk,
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            'You can add up to ${ProjectInput.maxAdditionalLinks} extra links.',
            style: TextStyle(fontSize: 11.5, color: tokens.textTertiary),
          ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: TextStyle(fontSize: 12, color: colors.error),
          ),
        ],
      ],
    );
  }
}

/// "Associated with" — an experience the user actually holds, or Personal /
/// Freelance.
///
/// Only the experience branch writes a backend field. Personal and Freelance
/// are stored as a description marker (see [ProjectInput.applyAssociation]),
/// because `experienceId` accepts a UUID or null and nothing else.
class _AssociationPicker extends ConsumerWidget {
  const _AssociationPicker({
    required this.association,
    required this.experienceId,
    required this.errorText,
    required this.onChanged,
  });

  final ProjectAssociation association;
  final String? experienceId;
  final String? errorText;
  final void Function(ProjectAssociation, String? experienceId) onChanged;

  static const Map<ProjectAssociation, String> _labels = {
    ProjectAssociation.experience: 'Experience',
    ProjectAssociation.personal: 'Personal',
    ProjectAssociation.freelance: 'Freelance',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final roles = ref.watch(myProfileProvider).value?.experiences ??
        const <ProfileEntry>[];
    final selectable = [
      for (final r in roles)
        if ((r.id ?? '').isNotEmpty) r,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Associated with', style: _formLabelStyle(context)),
        const SizedBox(height: 10),
        SheetChipGroup(
          options: _labels.values.toList(),
          selected: _labels[association],
          onSelected: (label) {
            final picked =
                _labels.entries.firstWhere((e) => e.value == label).key;
            onChanged(
              picked,
              picked == ProjectAssociation.experience ? experienceId : null,
            );
          },
        ),
        if (association == ProjectAssociation.experience) ...[
          const SizedBox(height: 12),
          if (selectable.isEmpty)
            Text(
              'Add a work experience first, or mark this as Personal or '
              'Freelance.',
              style: TextStyle(fontSize: 12, color: tokens.textTertiary),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in selectable)
                  _RoleChip(
                    label: role.subtitle.isEmpty ? role.title : role.subtitle,
                    sublabel: role.title,
                    selected: role.id == experienceId,
                    onTap: () => onChanged(
                      ProjectAssociation.experience,
                      role.id,
                    ),
                  ),
              ],
            ),
        ],
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(errorText!, style: TextStyle(fontSize: 12, color: colors.error)),
        ],
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    // Selected lifts a tier behind the interactive edge (the shared filter
    // contract) rather than filling with the brand.
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? colors.surfaceContainerHigh : tokens.surfaceInset,
            borderRadius: AppRadii.smallAll,
            border: Border.all(color: tokens.lineInteractive),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 10.5,
                  color: tokens.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cover banner at the top of the project form: an empty gray "Add Cover"
/// zone, or the picked/saved image with a "Change Cover" pill + red remove ✕.
class _ProjectCoverZone extends StatelessWidget {
  const _ProjectCoverZone({
    required this.onTapCover,
    this.file,
    this.url,
    this.onRemove,
  });

  final File? file;
  final String? url;
  final VoidCallback onTapCover;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final filled = file != null || (url != null && url!.isNotEmpty);
    final well = ColoredBox(color: ProfileSurfaceTokens.of(context).insetFill);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ProfileSurfaceTokens.nestedRadius),
      child: SizedBox(
        height: 156,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file != null)
              Image.file(file!, fit: BoxFit.cover)
            else if (url != null && url!.isNotEmpty)
              Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => well,
              )
            else
              well,
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CoverPill(
                    label: filled ? 'Change Cover' : 'Add Cover',
                    onTap: onTapCover,
                  ),
                  if (filled && onRemove != null) ...[
                    const SizedBox(width: 6),
                    Semantics(
                      button: true,
                      label: 'Remove cover',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: onRemove,
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox.square(
                          dimension: 44,
                          child: Center(
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.error,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close,
                                  size: 17, color: colors.onError),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Add Cover" / "Change Cover" on the project cover: the cover chrome's
/// charcoal glass pill, legible over any picked image and over the empty well.
class _CoverPill extends StatelessWidget {
  const _CoverPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ProfileGlassPill(
      icon: Icons.photo_camera_outlined,
      label: label,
      height: 40,
      onTap: onTap,
    );
  }
}

/// The project form's destructive action: the app's destructive outline —
/// never a red slab, so it cannot outrank the Save beside it.
class _DeleteProjectButton extends StatelessWidget {
  const _DeleteProjectButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton.destructive(
      label: 'Delete Project',
      leading: Icons.delete_outline,
      onPressed: onTap,
    );
  }
}

/// The shared form-label style.
///
/// A function rather than a constant: the ink comes from the active theme, so
/// it cannot be resolved once at library load.
TextStyle _formLabelStyle(BuildContext context) => TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );

// ════════════════════════════════════════════════════════════════════════════
// Photo picking + presigned image upload (avatar / banner / project cover)
// ════════════════════════════════════════════════════════════════════════════

/// Content type for an image path, limited to the backend's allowed set
/// (jpeg/jpg/png/webp); defaults to jpeg.
String _imageMimeFor(String path) {
  switch (_extensionOf(path)) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1 || dot == path.length - 1) return 'jpg';
  return path.substring(dot + 1).toLowerCase();
}

/// Picks a single image from the gallery, returning the local file (or null if
/// cancelled).
Future<File?> _pickImageFile() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 88,
    maxWidth: 2000,
  );
  return picked == null ? null : File(picked.path);
}

/// Picks and uploads an avatar/banner image via the presigned flow. Returns
/// true on success, false on failure, null when the user cancelled the picker.
Future<bool?> _pickAndUploadImage(WidgetRef ref,
    {required bool isBanner}) async {
  final file = await _pickImageFile();
  if (file == null) return null;
  final repo = ref.read(profileMediaRepositoryProvider);
  final path = file.path;
  final name = path.split('/').last;
  final mime = _imageMimeFor(path);
  try {
    if (isBanner) {
      await repo.uploadBanner(filePath: path, fileName: name, mimeType: mime);
    } else {
      await repo.uploadProfilePicture(
          filePath: path, fileName: name, mimeType: mime);
    }
    await _syncProfileMediaChange(ref);
    return true;
  } catch (_) {
    return false;
  }
}

/// After the signed-in user changes their photo/banner: refresh the cached auth
/// user (the JWT user is frozen at login, so the app chrome would otherwise
/// keep showing the stale login-time avatar until relaunch) and rebuild the
/// surfaces that display it — the profile screen, the drawer identity block,
/// and the Home header + own-post feed avatars.
Future<void> _syncProfileMediaChange(WidgetRef ref) async {
  await AuthManager().refreshCurrentUser();
  ref.invalidate(myProfileProvider);
  ref.invalidate(profileSummaryProvider);
  ref.invalidate(homeFeedProvider);
}

/// A small action sheet to change / remove the profile photo (or banner). One
/// tap picks + uploads via the presigned flow; the profile refreshes live.
Future<void> showProfilePhotoSheet(BuildContext context,
    {required bool isBanner}) {
  return showProfileSheet(context,
      builder: (_) => _PhotoActionSheet(isBanner: isBanner));
}

class _PhotoActionSheet extends ConsumerStatefulWidget {
  const _PhotoActionSheet({required this.isBanner});

  final bool isBanner;

  @override
  ConsumerState<_PhotoActionSheet> createState() => _PhotoActionSheetState();
}

class _PhotoActionSheetState extends ConsumerState<_PhotoActionSheet> {
  bool _busy = false;

  Future<void> _choose() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _pickAndUploadImage(ref, isBanner: widget.isBanner);
    if (!mounted) return;
    if (ok == null) {
      setState(() => _busy = false); // cancelled
      return;
    }
    if (ok) {
      context.showSnackBar(
          widget.isBanner ? 'Cover photo updated' : 'Photo updated');
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
      context.showErrorSnackBar("Couldn't update. Please try again.");
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(profileMediaRepositoryProvider);
      if (widget.isBanner) {
        await repo.deleteBanner();
      } else {
        await repo.deleteProfilePicture();
      }
      await _syncProfileMediaChange(ref);
      if (!mounted) return;
      context.showSnackBar(
          widget.isBanner ? 'Cover photo removed' : 'Photo removed');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      context.showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isBanner ? 'Cover Photo' : 'Profile Photo';
    return ProfileSheetScaffold(
      title: label,
      icon: widget.isBanner ? Icons.image_outlined : Icons.person_outline,
      tintedIcon: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhotoUploadZone(busy: _busy, onTap: _choose),
          const SizedBox(height: 8),
          Center(
            child: AppButton.text(
              label: 'Remove current ${widget.isBanner ? 'cover' : 'photo'}',
              leading: Icons.delete_outline,
              destructive: true,
              onPressed: _busy ? null : _remove,
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
