import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/profile_surface_tokens.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/state/submit_status.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/form_validators.dart';
import '../data/models/profile_edit.dart';
import '../data/models/user_profile.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_surface.dart';
import '../widgets/certifications_section.dart';
import '../widgets/edit_profile_widgets.dart';
import '../widgets/location_picker_sheet.dart';
import '../widgets/profile_edit_sheets.dart';
import '../widgets/references_section.dart';
import '../../../core/theme/theme_context_ext.dart';

/// The fields the save-time check can refuse, **in the order they appear on
/// screen** — so "the first invalid field" is the first one the person would
/// reach scrolling down, and that is where a refused save takes them.
enum EditProfileField {
  name('Full name'),
  headline('Headline'),
  website('Website'),
  bio('Bio');

  const EditProfileField(this.label);

  /// How the field is named in a message.
  final String label;
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _headlineController = TextEditingController();
  final _companyController = TextEditingController();
  final _locationController = TextEditingController();
  final _handleController = TextEditingController();
  final _websiteController = TextEditingController();
  final _bioController = TextEditingController();
  bool _openToWork = false;
  bool _seeded = false;
  UserProfile? _screenProfile;
  ProfileEdit? _lastSubmittedEdit;
  bool _awaitingFreshProfileAfterSave = false;

  // Inline save-time validation state; cleared as soon as the field changes.
  String? _nameError;
  String? _headlineError;
  String? _websiteError;
  String? _bioError;

  /// Set when the user picks a new location; drives the current-location write.
  String? _locationId;

  /// One focus node and one anchor per validated field. A refused save used to
  /// say "fix the highlighted fields" from wherever the person happened to be
  /// scrolled — with Bio two cards down, nothing on screen was highlighted.
  /// These let the screen bring the offending field into view with the cursor
  /// already in it.
  final Map<EditProfileField, FocusNode> _fieldFocus = {
    for (final f in EditProfileField.values)
      f: FocusNode(debugLabel: 'edit-profile:${f.name}'),
  };
  final Map<EditProfileField, GlobalKey> _fieldAnchors = {
    for (final f in EditProfileField.values)
      f: GlobalKey(debugLabel: 'edit-profile:${f.name}'),
  };

  @override
  void dispose() {
    for (final node in _fieldFocus.values) {
      node.dispose();
    }
    _nameController.dispose();
    _headlineController.dispose();
    _companyController.dispose();
    _locationController.dispose();
    _handleController.dispose();
    _websiteController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final profileAsync = ref.watch(myProfileProvider);
    final editState = ref.watch(profileEditControllerProvider);

    ref.listen(profileEditControllerProvider, (previous, next) {
      if (previous?.status != next.status &&
          next.status == SubmitStatus.success) {
        final submitted = _lastSubmittedEdit;
        if (submitted != null) {
          _applySavedDraft(submitted);
        }
        context.showSnackBar('Profile saved');
      } else if (previous?.error != next.error && next.error != null) {
        context.showErrorSnackBar(next.error!);
      }
    });

    final liveProfile = profileAsync.asData?.value;
    if (liveProfile != null) {
      if (_awaitingFreshProfileAfterSave) {
        final submitted = _lastSubmittedEdit;
        if (submitted != null && _profileMatchesEdit(liveProfile, submitted)) {
          _screenProfile = liveProfile;
          _awaitingFreshProfileAfterSave = false;
        }
      } else {
        _screenProfile = liveProfile;
      }
    }

    final profile = _screenProfile;

    return Scaffold(
      // The profile's near-black canvas: the edit surface is the profile, in
      // edit mode, so it sits on the same ground.
      backgroundColor: ProfileSurfaceTokens.of(context).canvas,
      body: SafeArea(
        child: Column(
          children: [
            EditProfileAppBar(
              onBack: () => Navigator.of(context).pop(),
              onSave: profile != null ? () => _save() : () {},
              isSaving: editState.status == SubmitStatus.submitting,
            ),
            const ProfileHairline(),
            Expanded(
              child: profile != null
                  ? Builder(
                      builder: (context) {
                        _seedControllers(profile);
                        return _EditProfileBody(
                          profile: profile,
                          nameController: _nameController,
                          headlineController: _headlineController,
                          companyController: _companyController,
                          locationController: _locationController,
                          handleController: _handleController,
                          websiteController: _websiteController,
                          bioController: _bioController,
                          openToWork: _openToWork,
                          onOpenToWorkChanged: (value) =>
                              setState(() => _openToWork = value),
                          onPickLocation: _pickLocation,
                          fieldFocus: _fieldFocus,
                          fieldAnchors: _fieldAnchors,
                          nameError: _nameError,
                          headlineError: _headlineError,
                          websiteError: _websiteError,
                          bioError: _bioError,
                          onNameChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                          onHeadlineChanged: (_) {
                            if (_headlineError != null) {
                              setState(() => _headlineError = null);
                            }
                          },
                          onWebsiteChanged: (_) {
                            if (_websiteError != null) {
                              setState(() => _websiteError = null);
                            }
                          },
                          onBioChanged: (_) {
                            if (_bioError != null) {
                              setState(() => _bioError = null);
                            }
                          },
                        );
                      },
                    )
                  : profileAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            error.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ),
                      data: (profile) {
                        _screenProfile = profile;
                        _seedControllers(profile);
                        return _EditProfileBody(
                          profile: profile,
                          nameController: _nameController,
                          headlineController: _headlineController,
                          companyController: _companyController,
                          locationController: _locationController,
                          handleController: _handleController,
                          websiteController: _websiteController,
                          bioController: _bioController,
                          openToWork: _openToWork,
                          onOpenToWorkChanged: (value) =>
                              setState(() => _openToWork = value),
                          onPickLocation: _pickLocation,
                          fieldFocus: _fieldFocus,
                          fieldAnchors: _fieldAnchors,
                          nameError: _nameError,
                          headlineError: _headlineError,
                          websiteError: _websiteError,
                          bioError: _bioError,
                          onNameChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                          onHeadlineChanged: (_) {
                            if (_headlineError != null) {
                              setState(() => _headlineError = null);
                            }
                          },
                          onWebsiteChanged: (_) {
                            if (_websiteError != null) {
                              setState(() => _websiteError = null);
                            }
                          },
                          onBioChanged: (_) {
                            if (_bioError != null) {
                              setState(() => _bioError = null);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _seedControllers(UserProfile profile) {
    // Company is derived from the current role, so unlike the typed fields it
    // has to keep tracking the profile after the first seed — editing the
    // Experience section changes it, and there's no user input to clobber.
    if (profile.experiences.isNotEmpty &&
        _companyController.text != profile.company) {
      _companyController.text = profile.company;
    }
    if (_seeded) return;
    _seeded = true;
    _nameController.text = profile.name;
    _headlineController.text = profile.title;
    _companyController.text = profile.company;
    _locationController.text = profile.location ?? '';
    _handleController.text = profile.handle;
    _websiteController.text = profile.website;
    _bioController.text = profile.about;
    _openToWork = profile.openToWork;
  }

  Future<void> _pickLocation() async {
    final loc = await showLocationPicker(context);
    if (loc != null && mounted) {
      setState(() {
        _locationId = loc.id;
        _locationController.text = loc.label;
      });
    }
  }

  /// Client-side checks before the profile PATCH. Surfaces every problem
  /// inline at once and returns what failed, in on-screen order; empty means
  /// the edit may be submitted.
  Map<EditProfileField, String> _validate() {
    final nameError = FormValidators.personName(_nameController.text);
    final headlineError = FormValidators.headline(_headlineController.text);
    final websiteError = FormValidators.webAddress(_websiteController.text);
    final bioError = FormValidators.bio(_bioController.text);
    setState(() {
      _nameError = nameError;
      _headlineError = headlineError;
      _websiteError = websiteError;
      _bioError = bioError;
    });
    return {
      if (nameError != null) EditProfileField.name: nameError,
      if (headlineError != null) EditProfileField.headline: headlineError,
      if (websiteError != null) EditProfileField.website: websiteError,
      if (bioError != null) EditProfileField.bio: bioError,
    };
  }

  /// What the snackbar says about a refused save.
  ///
  /// One problem: the validator's own sentence, so the toast and the inline
  /// message are the same words. Several: how many, and which one the screen
  /// just moved to — the rest are marked inline and cleared one at a time.
  static String _refusalMessage(Map<EditProfileField, String> invalid) {
    if (invalid.length == 1) return invalid.values.first;
    return '${invalid.length} fields need fixing, starting with '
        '${invalid.keys.first.label}.';
  }

  /// Scrolls [field] (label, input and the inline message under it) into view,
  /// then puts the cursor in it.
  ///
  /// In that order on purpose. A text field that gains focus runs its own
  /// "show the caret" scroll, and two animations on one scroll position do not
  /// blend — the later one simply replaces the earlier. Focusing first let the
  /// caret-only scroll win, which parks a multi-line Bio half under the fold
  /// with its message still out of sight. Once the field is already in view
  /// the caret scroll has nothing left to do.
  Future<void> _reveal(EditProfileField field) async {
    // After the frame that paints the error rows: they add height above the
    // later fields, so measuring now would aim at where the field used to be.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final anchor = _fieldAnchors[field]!.currentContext;
    if (anchor != null && anchor.mounted) {
      await Scrollable.ensureVisible(
        anchor,
        // A little below the top edge: the section heading stays readable
        // above the field, and the keyboard that is about to open has room.
        alignment: 0.15,
        duration: AppMotion.durationFor(context, AppMotion.enter),
        curve: AppMotion.curveFor(context, AppMotion.enterCurve),
      );
      if (!mounted) return;
    }
    _fieldFocus[field]!.requestFocus();
  }

  Future<void> _save() async {
    final invalid = _validate();
    if (invalid.isNotEmpty) {
      // No unfocus on this path — the keyboard is about to be wanted again.
      _reveal(invalid.keys.first);
      context.showErrorSnackBar(_refusalMessage(invalid));
      return;
    }
    FocusScope.of(context).unfocus();
    final edit = ProfileEdit(
      name: _nameController.text.trim(),
      headline: _headlineController.text.trim(),
      company: _companyController.text.trim(),
      location: _locationController.text.trim(),
      locationId: _locationId,
      handle: _handleController.text.trim(),
      website: FormValidators.normalizeUrl(_websiteController.text),
      about: _bioController.text.trim(),
      openToWork: _openToWork,
    );
    _lastSubmittedEdit = edit;
    await ref.read(profileEditControllerProvider.notifier).submit(edit);
  }

  void _applySavedDraft(ProfileEdit edit) {
    setState(() {
      _awaitingFreshProfileAfterSave = true;
      _nameController.text = edit.name;
      _headlineController.text = edit.headline;
      _companyController.text = edit.company;
      _locationController.text = edit.location;
      _websiteController.text = edit.website;
      _bioController.text = edit.about;
      _openToWork = edit.openToWork;
      _locationId = null;
      final base = _screenProfile;
      if (base != null) {
        _screenProfile = UserProfile(
          id: base.id,
          userId: base.userId,
          name: edit.name,
          title: edit.headline,
          profilePic: base.profilePic,
          banner: base.banner,
          location: edit.location.isEmpty ? null : edit.location,
          company: edit.company,
          department: base.department,
          industry: base.industry,
          handle: base.handle,
          website: edit.website,
          about: edit.about,
          openToWork: edit.openToWork,
          completionPercent: base.completionPercent,
          impressionCount: base.impressionCount,
          experiences: base.experiences,
          educations: base.educations,
          skills: base.skills,
          categorizedSkills: base.categorizedSkills,
          technicalSkills: base.technicalSkills,
          languages: base.languages,
          projects: base.projects,
          links: base.links,
          bannerColor: base.bannerColor,
          skillCategoryColors: base.skillCategoryColors,
          introMediaUrl: base.introMediaUrl,
          introMediaType: base.introMediaType,
          introMediaPublic: base.introMediaPublic,
        );
      }
    });
  }

  bool _profileMatchesEdit(UserProfile profile, ProfileEdit edit) {
    final location = profile.location ?? '';
    return profile.name == edit.name &&
        profile.title == edit.headline &&
        profile.company == edit.company &&
        location == edit.location &&
        profile.website == edit.website &&
        profile.about == edit.about &&
        profile.openToWork == edit.openToWork;
  }
}

class _EditProfileBody extends StatelessWidget {
  final UserProfile profile;
  final TextEditingController nameController;
  final TextEditingController headlineController;
  final TextEditingController companyController;
  final TextEditingController locationController;
  final TextEditingController handleController;
  final TextEditingController websiteController;
  final TextEditingController bioController;
  final bool openToWork;
  final ValueChanged<bool> onOpenToWorkChanged;
  final VoidCallback onPickLocation;

  /// Focus node + scroll anchor per validated field (owned by the screen).
  final Map<EditProfileField, FocusNode> fieldFocus;
  final Map<EditProfileField, GlobalKey> fieldAnchors;

  // Inline validation state + clear-on-edit callbacks (owned by the screen).
  final String? nameError;
  final String? headlineError;
  final String? websiteError;
  final String? bioError;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onHeadlineChanged;
  final ValueChanged<String> onWebsiteChanged;
  final ValueChanged<String> onBioChanged;

  const _EditProfileBody({
    required this.profile,
    required this.nameController,
    required this.headlineController,
    required this.companyController,
    required this.locationController,
    required this.handleController,
    required this.websiteController,
    required this.bioController,
    required this.openToWork,
    required this.onOpenToWorkChanged,
    required this.onPickLocation,
    required this.fieldFocus,
    required this.fieldAnchors,
    required this.nameError,
    required this.headlineError,
    required this.websiteError,
    required this.bioError,
    required this.onNameChanged,
    required this.onHeadlineChanged,
    required this.onWebsiteChanged,
    required this.onBioChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 0, bottom: 18),
      child: Column(
        children: [
          ProfileCoverHeader(
            bannerUrl: profile.banner ?? '',
            bannerColor: profile.bannerColor,
            avatarUrl: profile.profilePic,
            name: profile.name,
            onEditCover: () => openEditCoverSheet(context),
            onEditAvatar: () => openProfilePhotoSheet(context),
          ),
          ProfileSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.person_outline,
                  title: 'Basic Info',
                ),
                const SizedBox(height: 10),
                // Caps come from the website's shared schema
                // (USER_NAME_MAX_LENGTH / USER_TITLE_MAX_LENGTH), which is the
                // same schema its API validates against — so an over-long value
                // is now stopped here instead of bouncing off the server.
                BasicInfoField(
                  key: fieldAnchors[EditProfileField.name],
                  focusNode: fieldFocus[EditProfileField.name],
                  label: 'FULL NAME',
                  icon: Icons.person_outline,
                  controller: nameController,
                  errorText: nameError,
                  onChanged: onNameChanged,
                  maxLength: FormValidators.nameMaxLength,
                ),
                BasicInfoField(
                  key: fieldAnchors[EditProfileField.headline],
                  focusNode: fieldFocus[EditProfileField.headline],
                  label: 'HEADLINE / TITLE',
                  icon: Icons.auto_awesome,
                  controller: headlineController,
                  errorText: headlineError,
                  onChanged: onHeadlineChanged,
                  maxLength: FormValidators.headlineMaxLength,
                ),
                // Once there's work history, the company is *derived* from the
                // current/latest role rather than being an independent value —
                // letting it be typed here is how Basic Info and the timeline
                // drifted apart in the first place. With no history yet it
                // stays free text (fresher / recruiter accounts).
                BasicInfoField(
                  label: 'COMPANY',
                  icon: Icons.business_outlined,
                  controller: companyController,
                  readOnly: profile.experiences.isNotEmpty,
                  note: profile.experiences.isEmpty
                      ? null
                      : 'From your current role. Change it under Experience',
                ),
                // Location is a tap-to-search picker: it supplies the real
                // locationId that `current-location` needs, then persists on Save.
                BasicInfoField(
                  label: 'LOCATION',
                  icon: Icons.location_on_outlined,
                  controller: locationController,
                  onTap: onPickLocation,
                  note: 'Tap to search and update your city',
                ),
                // No documented endpoint updates the handle (it's the account's
                // unique userId), so it's read-only.
                BasicInfoField(
                  label: 'HANDLE',
                  icon: Icons.alternate_email,
                  controller: handleController,
                  readOnly: true,
                  note: 'Your handle cannot be changed here',
                ),
                BasicInfoField(
                  key: fieldAnchors[EditProfileField.website],
                  focusNode: fieldFocus[EditProfileField.website],
                  label: 'WEBSITE',
                  icon: Icons.link,
                  controller: websiteController,
                  showDivider: false,
                  errorText: websiteError,
                  onChanged: onWebsiteChanged,
                ),
                OpenToWorkRow(
                  value: openToWork,
                  onChanged: onOpenToWorkChanged,
                ),
              ],
            ),
          ),
          ProfileSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.description_outlined,
                  title: 'About / Bio',
                ),
                const SizedBox(height: 10),
                AboutBioField(
                  key: fieldAnchors[EditProfileField.bio],
                  focusNode: fieldFocus[EditProfileField.bio],
                  controller: bioController,
                  errorText: bioError,
                  onChanged: onBioChanged,
                ),
              ],
            ),
          ),
          ProfileSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One action per section: "+" when empty, edit once it has data.
                SectionHeader(
                  icon: Icons.work_outline,
                  title: 'Experience',
                  showAdd: profile.experiences.isEmpty,
                  showEdit: profile.experiences.isNotEmpty,
                  onAdd: () =>
                      openExperienceSheet(context, profile.experiences),
                  onEdit: () =>
                      openExperienceSheet(context, profile.experiences),
                ),
                if (profile.experiences.isEmpty)
                  const SectionEmptyState(
                    icon: Icons.work_outline,
                    title: 'Add your work experience',
                    subtitle: "Let others know what you're working on.",
                  )
                else
                  for (int i = 0; i < profile.experiences.length; i++)
                    _experienceCard(context, profile.experiences[i], i),
              ],
            ),
          ),
          ProfileSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  icon: Icons.school_outlined,
                  title: 'Education',
                  showAdd: profile.educations.isEmpty,
                  showEdit: profile.educations.isNotEmpty,
                  onAdd: () => openEducationSheet(context, profile.educations),
                  onEdit: () => openEducationSheet(context, profile.educations),
                ),
                if (profile.educations.isEmpty)
                  const SectionEmptyState(
                    icon: Icons.school_outlined,
                    title: 'Add your education',
                    subtitle: 'Showcase your academic background.',
                  )
                else
                  for (final entry in profile.educations)
                    EducationCard(entry: entry),
              ],
            ),
          ),
          ProfileSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  icon: Icons.star_border,
                  title: 'Skills',
                  showAdd: profile.categorizedSkills.isEmpty,
                  showEdit: profile.categorizedSkills.isNotEmpty,
                  onAdd: () => openSkillsSheet(context,
                      profile.categorizedSkills, profile.skillCategoryColors),
                  onEdit: () => openSkillsSheet(context,
                      profile.categorizedSkills, profile.skillCategoryColors),
                ),
                if (profile.categorizedSkills.isEmpty)
                  const SectionEmptyState(
                    icon: Icons.star_border,
                    title: 'Add your skills',
                    subtitle: 'Skills help recruiters and peers find you.',
                  )
                else
                  for (final category in profile.categorizedSkills.entries)
                    SkillCategoryBlock(
                      title: category.key,
                      values: category.value,
                      accent: profileDisplayAccent(
                          profile.skillCategoryColors[category.key]),
                    ),
              ],
            ),
          ),
          if (profile.technicalSkills.isNotEmpty)
            ProfileSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    icon: Icons.tune,
                    title: 'Technical Skills',
                  ),
                  for (final skill in profile.technicalSkills)
                    TechnicalSkillRow(skill: skill),
                ],
              ),
            ),
          ProfileSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  icon: Icons.language,
                  title: 'Languages',
                  showAdd: profile.languages.isEmpty,
                  showEdit: profile.languages.isNotEmpty,
                  onAdd: () => openLanguagesSheet(context, profile.languages),
                  onEdit: () => openLanguagesSheet(context, profile.languages),
                ),
                if (profile.languages.isEmpty)
                  const SectionEmptyState(
                    icon: Icons.language,
                    title: 'Add languages you speak',
                    subtitle: 'Showcase your language skills.',
                  )
                else
                  for (final language in profile.languages)
                    LanguageRow(language: language),
              ],
            ),
          ),
          ProfileSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.image_outlined,
                  title: 'Proof of Work',
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: profile.projects.length + 1,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.3,
                  ),
                  itemBuilder: (context, index) {
                    if (index == profile.projects.length) {
                      return ProjectTile(
                        isAddTile: true,
                        onTap: () => openProjectSheet(context),
                      );
                    }
                    final project = profile.projects[index];
                    return GestureDetector(
                      onTap: () => openProjectSheet(context, project: project),
                      child: ProjectTile(project: project),
                    );
                  },
                ),
              ],
            ),
          ),
          // Both fetch their own data (neither rides on `/work-details`), so
          // they're dropped in as self-contained cards rather than being fed
          // from `profile`.
          const ReferencesSectionCard(editable: true),
          const CertificationsSectionCard(editable: true),
        ],
      ),
    );
  }

  /// Experience entries render their saved accent when they have one; the rest
  /// take the neutral rail. Same rule as the profile view's
  /// `ExperienceSectionCard`, so the edit screen shows what the profile shows.
  /// The current/"Now" role keeps its green badge.
  Widget _experienceCard(BuildContext context, ProfileEntry entry, int index) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    final custom = profileDisplayAccent(entry.accentColorHex);
    final isNow = (entry.trailingBadge ?? '').toLowerCase() == 'now';
    return EntryCard(
      entry: entry,
      accent: custom,
      badgeBackground: isNow
          ? tokens.successContainer
          : (custom?.withAlpha(28) ?? colors.surfaceContainerHigh),
      badgeForeground: isNow
          ? tokens.onSuccessContainer
          : (custom ?? colors.onSurfaceVariant),
    );
  }
}
