import 'package:flutter/material.dart';

import 'brand_palette.dart';

/// SyncUp's semantic colour roles that Material 3's [ColorScheme] does not
/// model.
///
/// ## What belongs here
///
/// A role earns a slot only if [ColorScheme] genuinely cannot express it.
/// "Success" and "warning" qualify — M3 has no such roles. A message bubble
/// pair qualifies — it is two paired surfaces with their own foregrounds. A
/// generic card background does **not** qualify; that is
/// `colorScheme.surfaceContainerLow`.
///
/// Roles are named for the job they do, never for the colour they happen to be.
/// `notificationUnread`, not `lavenderCard`. When the dark value is a different
/// hue from the light one — which is the normal case — a colour-derived name
/// becomes a lie.
///
/// ## Reading these
///
/// ```dart
/// final tokens = context.tokens;  // see theme_context_ext.dart
/// Container(color: tokens.messageIncoming);
/// ```
///
/// ## Fixed roles
///
/// A few roles are identical in both themes on purpose — media grounds, the
/// profile hero, the logo tile. Each carries a comment saying why. They are
/// here rather than as bare constants so consumers still go through one API and
/// the exemption is visible at the point of definition.
@immutable
class SyncUpSemantics extends ThemeExtension<SyncUpSemantics> {
  const SyncUpSemantics({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.infoContainer,
    required this.textTertiary,
    required this.textDisabled,
    required this.inputFill,
    required this.inputFillDisabled,
    required this.fieldFocusRim,
    required this.skeleton,
    required this.cardShadow,
    required this.barSeparator,
    required this.messageIncoming,
    required this.onMessageIncoming,
    required this.messageOutgoing,
    required this.onMessageOutgoing,
    required this.notificationUnread,
    required this.presenceOnline,
    required this.unreadIndicator,
    required this.swipeDestructive,
    required this.swipeFavorite,
    required this.destructiveInk,
    required this.surfaceInset,
    required this.ctaFill,
    required this.onCtaFill,
    required this.brandSurface,
    required this.lineSubtle,
    required this.lineDefault,
    required this.lineStrong,
    required this.lineInteractive,
    required this.controlInk,
    required this.controlOutline,
    required this.iconTile,
    required this.iconInk,
    required this.reactionLike,
    required this.heroSurfaceStart,
    required this.heroSurfaceEnd,
    required this.onHeroSurface,
    required this.mediaSurface,
    required this.onMediaSurface,
    required this.uploadZoneFill,
    required this.uploadZoneBorder,
    required this.logoTile,
    required this.avatarPalette,
  });

  // ── Status ─────────────────────────────────────────────────────────────────
  // M3 models `error` but has no success, warning or info role. The app has all
  // three: upload success cards, the amber system-notification icon, and
  // informational note surfaces.

  /// Success ink — confirmations, the salary figure on job cards, the
  /// "favourite" swipe.
  final Color success;

  /// Success surface — the upload success card, the green stat tile.
  final Color successContainer;

  /// Ink on [successContainer].
  final Color onSuccessContainer;

  /// Warning ink — the system-notification glyph, mid password strength.
  final Color warning;

  /// Warning surface — the amber disc behind a system notification.
  final Color warningContainer;

  /// Ink on [warningContainer].
  final Color onWarningContainer;

  /// Informational ink. Distinct from `colorScheme.primary`, which means
  /// "the brand action" — an info notice is not an action.
  final Color info;

  /// Informational surface — note and callout backgrounds.
  final Color infoContainer;

  // ── Text ───────────────────────────────────────────────────────────────────
  // M3 gives two ink tones on a surface (`onSurface`, `onSurfaceVariant`).
  // SyncUp's type scale uses four.

  /// The third ink tone — timestamps, captions, placeholder text. Quieter than
  /// `onSurfaceVariant`, still required to clear 4.5:1.
  final Color textTertiary;

  /// Disabled ink. Exempt from WCAG contrast, but must stay distinguishable
  /// from enabled text in both themes.
  final Color textDisabled;

  // ── Inputs ─────────────────────────────────────────────────────────────────

  /// Filled-field background.
  final Color inputFill;

  /// Filled-field background when disabled or read-only.
  final Color inputFillDisabled;

  /// The edge of a text-entry control that has focus — every kind of one: the
  /// Material `InputDecorationTheme` border, a glass field's rim, an OTP box.
  ///
  /// **One value, so focus looks the same on every form.** In dark it is a
  /// calm cool grey rather than the near-white [controlInk] or the brand
  /// accent: a focused field is announcing a *state*, not competing with the
  /// screen's primary action, and it must never read as a light source. It
  /// still clears 3:1 (WCAG 1.4.11) against both the page and a field's fill.
  /// The width that goes with it is `AppInputTheme.focusRimWidth`.
  final Color fieldFocusRim;

  // ── Loading ────────────────────────────────────────────────────────────────

  /// Placeholder block shown while remote media loads.
  ///
  /// Must read as *lighter* than the surface behind it in **both** themes. A
  /// skeleton darker than its page reads as a hole rather than a pending image.
  final Color skeleton;

  // ── Elevation ──────────────────────────────────────────────────────────────

  /// The ambient card shadow.
  ///
  /// A list rather than a `Color`, because it carries blur and offset — and
  /// because in dark mode the correct value is an **empty list**: a black
  /// shadow on a dark ground is invisible. Cards separate by surface tier and
  /// an `outlineVariant` border there instead.
  final List<BoxShadow> cardShadow;

  /// The line separating fixed chrome from scrolling content — sticky action
  /// bars, the bottom nav's top edge. In light this pairs with a soft upward
  /// shadow; in dark it does the whole job alone.
  final Color barSeparator;

  // ── Messaging ──────────────────────────────────────────────────────────────
  // Two paired surfaces with their own foregrounds. Shared by the chat feature
  // and the AI readiness sprint so the two conversation surfaces stay identical.

  final Color messageIncoming;
  final Color onMessageIncoming;
  final Color messageOutgoing;
  final Color onMessageOutgoing;

  // ── Status indicators ──────────────────────────────────────────────────────

  /// Unread notification card fill. A meaning-bearing surface tint.
  ///
  /// Note for the migration: read/unread is currently encoded by this colour
  /// *alone*, which fails WCAG 1.4.1. Whichever phase migrates the
  /// notifications feature must also add a non-colour affordance.
  final Color notificationUnread;

  /// The "online" presence dot.
  final Color presenceOnline;

  /// The unread dot on the notification bell. Four feature palettes define this
  /// independently today.
  final Color unreadIndicator;

  /// Swipe-to-delete panel. Not `colorScheme.error`: this is a gesture
  /// affordance, not an error state, and the two should be free to diverge.
  final Color swipeDestructive;

  /// Swipe-to-favourite panel.
  final Color swipeFavorite;

  /// Ink for a destructive action rendered as **text or an outline** rather
  /// than as a red fill — "Log Out", "Delete Account", "Remove connection".
  ///
  /// Not `colorScheme.error`, and the difference is the point: `error` is tuned
  /// to carry white on top of it as a *background*, where 3:1 is the bar. The
  /// moment the destructive choice becomes the secondary button — which is what
  /// a safe-primary hierarchy requires — that same red becomes foreground text
  /// against the page and has to clear 4.5:1. In light mode it does not, so
  /// this role is a darker shade; in dark mode it resolves to the same value as
  /// `error`, which already passes comfortably.
  final Color destructiveInk;

  // ── Aperture: surfaces, action and lines ───────────────────────────────────

  /// The tier **below** the page: input wells, media letterboxes, code blocks.
  ///
  /// `ColorScheme` has no role for "recessed" — `surfaceContainerLowest` is the
  /// nearest, and on dark it now resolves to this same value. It is named here
  /// because "inset" is a statement about depth, and a component asking for a
  /// well should not have to know which container tier happens to sit lowest.
  final Color surfaceInset;

  /// The **primary action fill**, and the single largest idea in the dark
  /// theme: on a near-black screen the highest-emphasis thing available is
  /// light, not hue.
  ///
  /// Deliberately *not* `colorScheme.primary`. 317 call sites read that role
  /// for chips, tabs, indicators, spinners and link ink; making it near-white
  /// would bleach all of them. This role is consumed by
  /// `AppButtonThemes.elevated` / `.filled` only, so exactly one class of
  /// control changes.
  ///
  /// In light it stays the brand blue — "maximum-contrast fill" is the rule,
  /// and inverting to near-black-on-white there would flip an established
  /// hierarchy this phase is not authorised to touch.
  final Color ctaFill;

  /// Label and glyph colour on [ctaFill]. 17.7:1 in dark.
  final Color onCtaFill;

  /// The one brand-tinted *fill* permitted on a dark surface — an outgoing
  /// message bubble, an unread row. Both encode "mine / new", which is the only
  /// job a tinted surface still has.
  ///
  /// Anything else wanting a brand wash should use brand *ink* on a neutral
  /// surface instead.
  final Color brandSurface;

  /// Hairline between rows, and the edge of a card that needs no emphasis.
  ///
  /// **Decorative.** Must never be the only thing communicating a state; see
  /// [lineInteractive].
  final Color lineSubtle;

  /// A container edge that should read as an edge. Still decorative.
  final Color lineDefault;

  /// A divider that has to carry across a raised surface. Still decorative.
  final Color lineStrong;

  /// The only line value that clears WCAG 1.4.11's **3:1** for non-text
  /// contrast, and therefore the only one allowed on a boundary that conveys
  /// state: an unselected segment, a checkbox outline, a focused edge.
  final Color lineInteractive;

  // ── Neutral control chrome ─────────────────────────────────────────────────
  // The dark theme used `colorScheme.primary` for almost every piece of
  // interactive chrome that was not a filled CTA: the "+" on a section header,
  // an outlined button's edge and label, a selected tab's underline, a dashed
  // upload zone, the tile behind a section icon, an empty state's disc. With
  // all of those in one hue, a single screen carried a dozen competing indigo
  // marks and nothing read as the primary action. These four roles split that
  // one colour into the jobs it was doing. In **light** each resolves to the
  // brand blue those controls already ship with, so light is unchanged; in
  // **dark** they resolve to the graphite ramp, so hierarchy is carried by
  // contrast, weight and shape rather than by hue. `primary` itself stays
  // indigo for the compact roles it is still right for — link text, mentions,
  // status dots, the brand mark.

  /// Ink for the chrome of a secondary interactive control: an add "+" or an
  /// edit pencil, an outlined button's label and glyph, a selected tab's label
  /// and its underline, a focused field's edge, a progress fill, a checked
  /// mark. Dark is near-white — a control announces itself by contrast and
  /// weight, not by hue.
  final Color controlInk;

  /// The boundary of such a control: an outlined button, an "add" tile's
  /// dashed edge, a Connect pill. Dark resolves to [lineInteractive], the one
  /// line value that clears WCAG 1.4.11's 3:1, because with a quiet fill the
  /// edge is what says "control".
  final Color controlOutline;

  /// The tile behind a decorative or informational glyph: a section icon, an
  /// empty state's disc, an initials fallback, a menu row's leading icon. Dark
  /// is the control tier of the graphite ramp — a tonal step, not a tint.
  final Color iconTile;

  /// Ink for such a glyph, on [iconTile] or straight on a surface. Dark is the
  /// **secondary** ink on purpose: a section icon decorates the heading beside
  /// it and must not outrank it.
  final Color iconInk;

  /// The active Like reaction. Not `colorScheme.error` — a liked post is not an
  /// error, and this red is deliberately warmer.
  final Color reactionLike;

  // ── Fixed surfaces ─────────────────────────────────────────────────────────

  /// Profile hero gradient, top stop.
  ///
  /// **Fixed in both themes.** The hero is a deliberately dark island inside a
  /// light app. In dark mode it keeps these values and gains a boundary
  /// (`outlineVariant`) instead, or it would dissolve into the page.
  final Color heroSurfaceStart;

  /// Profile hero gradient, bottom stop. Fixed — see [heroSurfaceStart].
  final Color heroSurfaceEnd;

  /// Ink on the hero. Fixed — see [heroSurfaceStart].
  final Color onHeroSurface;

  /// Full-bleed media ground — the post image viewer, the intro video player.
  ///
  /// **Fixed black in both themes.** Photo and video content is viewed against
  /// black regardless of app appearance; that is the platform convention and it
  /// is what the content was framed for.
  final Color mediaSurface;

  /// Ink and controls on [mediaSurface]. Fixed.
  final Color onMediaSurface;

  // ── Upload ─────────────────────────────────────────────────────────────────
  // Consumed by `dotted_border`, which takes an explicit colour and cannot
  // inherit from the theme.

  final Color uploadZoneFill;
  final Color uploadZoneBorder;

  // ── Media tiles ────────────────────────────────────────────────────────────

  /// The tile behind a company logo.
  ///
  /// Stays **light in both themes**, which looks unusual on a dark page and is
  /// intentional: company logos are third-party artwork, frequently dark marks
  /// on a transparent ground, and a dark tile would erase them.
  final Color logoTile;

  /// The generated-avatar colour ramp, indexed by a hash of the user's name.
  ///
  /// A list, and the dark variant is lifted — the light ramp's mid-tones sit
  /// too close to a dark page to read as distinct discs.
  final List<Color> avatarPalette;

  // ── Light ──────────────────────────────────────────────────────────────────

  static const SyncUpSemantics light = SyncUpSemantics(
    success: BrandPalette.green600,
    successContainer: BrandPalette.green50,
    onSuccessContainer: BrandPalette.green700,
    warning: BrandPalette.amber600,
    warningContainer: BrandPalette.amber50,
    onWarningContainer: BrandPalette.amber600,
    info: BrandPalette.blue600,
    infoContainer: BrandPalette.cyan50,

    textTertiary: BrandPalette.ink500,
    textDisabled: BrandPalette.ink250,

    // Exactly the pre-theme `InputDecorationTheme.fillColor` (`bgLight`).
    inputFill: BrandPalette.blue25,
    inputFillDisabled: BrandPalette.ink30,
    // The brand blue light's focused fields already carry.
    fieldFocusRim: BrandPalette.blue600,

    skeleton: BrandPalette.ink50,

    // The value `kHomeCardShadow`, `kJobsCardShadow`, `kNetworkCardShadow`,
    // `kSavedCardShadow` and `_kSettingsCardShadow` all independently define.
    cardShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x12000000),
        blurRadius: 16,
        offset: Offset(0, 5),
      ),
    ],
    barSeparator: BrandPalette.ink70,

    messageIncoming: BrandPalette.bubbleIncomingLight,
    onMessageIncoming: BrandPalette.ink900,
    messageOutgoing: BrandPalette.bubbleOutgoingLight,
    onMessageOutgoing: BrandPalette.ink900,

    notificationUnread: BrandPalette.violet100,
    presenceOnline: BrandPalette.green450,
    unreadIndicator: BrandPalette.green450,
    swipeDestructive: BrandPalette.red650,
    swipeFavorite: BrandPalette.green650,
    destructiveInk: BrandPalette.red800,

    // Light keeps the brand fill for primary actions. The Aperture rule is
    // "maximum-contrast fill"; on white that would resolve to near-black, which
    // is a hierarchy change this phase is not scoped to make. Revisit when the
    // light theme is designed rather than preserved.
    surfaceInset: BrandPalette.ink30,
    ctaFill: BrandPalette.blue600,
    onCtaFill: BrandPalette.white,
    brandSurface: BrandPalette.blue50,
    lineSubtle: BrandPalette.ink120,
    lineDefault: BrandPalette.ink100,
    lineStrong: BrandPalette.ink150,
    // ink500, not the lighter ink300 the ramp would suggest: this role is the
    // one line value allowed to carry state, so it owes 3:1. ink300 measures
    // 2.3:1 on white; ink500 measures 4.0:1.
    lineInteractive: BrandPalette.ink500,
    // Light keeps the brand for its control chrome — exactly what these
    // controls rendered before the roles existed.
    controlInk: BrandPalette.blue600,
    controlOutline: BrandPalette.blue600,
    iconTile: BrandPalette.blue50,
    iconInk: BrandPalette.blue600,
    reactionLike: BrandPalette.red700,

    heroSurfaceStart: BrandPalette.heroIndigoDeep,
    heroSurfaceEnd: BrandPalette.heroIndigo,
    onHeroSurface: BrandPalette.white,
    mediaSurface: BrandPalette.mediaBlack,
    onMediaSurface: BrandPalette.white,

    uploadZoneFill: BrandPalette.blue100,
    uploadZoneBorder: BrandPalette.blue350,

    logoTile: BrandPalette.logoTileLight,
    avatarPalette: BrandPalette.avatarRampLight,
  );

  // ── Dark ───────────────────────────────────────────────────────────────────

  static const SyncUpSemantics dark = SyncUpSemantics(
    success: BrandPalette.green300,
    successContainer: BrandPalette.green900,
    onSuccessContainer: BrandPalette.green300,
    warning: BrandPalette.amber300,
    warningContainer: BrandPalette.amber900,
    onWarningContainer: BrandPalette.amber300,
    info: BrandPalette.blue500,
    infoContainer: BrandPalette.cyan800,

    textTertiary: BrandPalette.graphiteInk500,
    textDisabled: BrandPalette.graphiteInk700,

    // Inputs are now *wells*: the enabled fill sits on the inset tier, below
    // the page, while the disabled fill sits on the raised tier so a
    // read-only field reads as a card rather than as something to type in.
    inputFill: BrandPalette.graphite990,
    inputFillDisabled: BrandPalette.graphite900,
    // Cool grey, a step below the near-white control ink: visible as a state
    // change, quiet as a colour. ~8:1 on the input well, ~6:1 on a glass pane.
    fieldFocusRim: BrandPalette.graphiteInk300,

    // Lighter than the surface behind it, matching the light theme's intent
    // rather than its value.
    skeleton: BrandPalette.graphite800,

    // Empty on purpose: a black shadow is invisible on a dark ground. Consumers
    // fall back to a surface tier plus an `outlineVariant` border. An empty
    // list also keeps `lerp` well-defined against the light value.
    cardShadow: <BoxShadow>[],
    barSeparator: BrandPalette.graphiteLine200,

    messageIncoming: BrandPalette.graphite800,
    onMessageIncoming: BrandPalette.graphiteInk100,
    // The outgoing bubble is one of the two brand-tinted fills the system
    // still permits, so it shares its value with `brandSurface`.
    messageOutgoing: BrandPalette.indigoSurface,
    onMessageOutgoing: BrandPalette.graphiteInk100,

    notificationUnread: BrandPalette.violet900,
    presenceOnline: BrandPalette.green450,
    unreadIndicator: BrandPalette.green450,
    swipeDestructive: BrandPalette.red650,
    swipeFavorite: BrandPalette.green650,
    destructiveInk: BrandPalette.red300,

    surfaceInset: BrandPalette.graphite990,
    ctaFill: BrandPalette.graphiteInk100,
    onCtaFill: BrandPalette.graphite950,
    brandSurface: BrandPalette.indigoSurface,
    lineSubtle: BrandPalette.graphiteLine100,
    lineDefault: BrandPalette.graphiteLine200,
    lineStrong: BrandPalette.graphiteLine300,
    lineInteractive: BrandPalette.graphiteLine400,
    // Dark: control chrome is graphite. Near-white ink and a 3:1 edge for
    // things you press; the control tier and secondary ink for things you
    // merely look at.
    controlInk: BrandPalette.graphiteInk100,
    controlOutline: BrandPalette.graphiteLine400,
    iconTile: BrandPalette.graphite800,
    iconInk: BrandPalette.graphiteInk300,
    reactionLike: BrandPalette.red700,

    // Fixed — identical to light. See the field docs.
    heroSurfaceStart: BrandPalette.heroIndigoDeep,
    heroSurfaceEnd: BrandPalette.heroIndigo,
    onHeroSurface: BrandPalette.white,
    mediaSurface: BrandPalette.mediaBlack,
    onMediaSurface: BrandPalette.white,

    // Upload is an input affordance, not a selected state, so its resting
    // surface is neutral. The dashed edge is the interactive line rather than
    // the decorative one: an empty drop zone has nothing else to say "tap me"
    // with, and the edge is what keeps it discoverable on a near-black card.
    uploadZoneFill: BrandPalette.graphite900,
    uploadZoneBorder: BrandPalette.graphiteLine400,

    logoTile: BrandPalette.logoTileDark,
    avatarPalette: BrandPalette.avatarRampDark,
  );

  /// The profile's monochrome set: every status, brand and accent role
  /// collapses to white ink on neutral greys. Pairs with
  /// `SyncUpColorSchemes.mono`.
  static final SyncUpSemantics mono = dark.copyWith(
    success: const Color(0xFFFFFFFF),
    successContainer: const Color(0xFF141414),
    onSuccessContainer: const Color(0xFFFFFFFF),
    warning: const Color(0xFFE5E5E5),
    warningContainer: const Color(0xFF141414),
    onWarningContainer: const Color(0xFFE5E5E5),
    info: const Color(0xFFFFFFFF),
    infoContainer: const Color(0xFF141414),
    textTertiary: const Color(0xFF737373),
    textDisabled: const Color(0xFF525252),
    inputFill: const Color(0xFF0A0A0A),
    inputFillDisabled: const Color(0xFF111111),
    fieldFocusRim: const Color(0xFFFFFFFF),
    skeleton: const Color(0xFF1A1A1A),
    barSeparator: const Color(0xFF1F1F1F),
    messageOutgoing: const Color(0xFF1F1F1F),
    notificationUnread: const Color(0xFF141414),
    presenceOnline: const Color(0xFFFFFFFF),
    unreadIndicator: const Color(0xFFFFFFFF),
    surfaceInset: const Color(0xFF050505),
    ctaFill: const Color(0xFFFFFFFF),
    onCtaFill: const Color(0xFF000000),
    brandSurface: const Color(0xFF141414),
    lineSubtle: const Color(0xFF141414),
    lineDefault: const Color(0xFF1F1F1F),
    lineStrong: const Color(0xFF2E2E2E),
    lineInteractive: const Color(0xFF5C5C5C),
    controlInk: const Color(0xFFFFFFFF),
    controlOutline: const Color(0xFF5C5C5C),
    iconTile: const Color(0xFF141414),
    iconInk: const Color(0xFFD4D4D4),
    reactionLike: const Color(0xFFFFFFFF),
    heroSurfaceStart: const Color(0xFF000000),
    heroSurfaceEnd: const Color(0xFF141414),
    uploadZoneFill: const Color(0xFF0A0A0A),
    uploadZoneBorder: const Color(0xFF5C5C5C),
    // Initials are drawn in `onPrimary` (black here), so the discs are light.
    avatarPalette: const [
      Color(0xFFF5F5F5),
      Color(0xFFE5E5E5),
      Color(0xFFD4D4D4),
      Color(0xFFEDEDED),
    ],
  );

  @override
  SyncUpSemantics copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? infoContainer,
    Color? textTertiary,
    Color? textDisabled,
    Color? inputFill,
    Color? inputFillDisabled,
    Color? fieldFocusRim,
    Color? skeleton,
    List<BoxShadow>? cardShadow,
    Color? barSeparator,
    Color? messageIncoming,
    Color? onMessageIncoming,
    Color? messageOutgoing,
    Color? onMessageOutgoing,
    Color? notificationUnread,
    Color? presenceOnline,
    Color? unreadIndicator,
    Color? swipeDestructive,
    Color? swipeFavorite,
    Color? destructiveInk,
    Color? surfaceInset,
    Color? ctaFill,
    Color? onCtaFill,
    Color? brandSurface,
    Color? lineSubtle,
    Color? lineDefault,
    Color? lineStrong,
    Color? lineInteractive,
    Color? controlInk,
    Color? controlOutline,
    Color? iconTile,
    Color? iconInk,
    Color? reactionLike,
    Color? heroSurfaceStart,
    Color? heroSurfaceEnd,
    Color? onHeroSurface,
    Color? mediaSurface,
    Color? onMediaSurface,
    Color? uploadZoneFill,
    Color? uploadZoneBorder,
    Color? logoTile,
    List<Color>? avatarPalette,
  }) {
    return SyncUpSemantics(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      inputFill: inputFill ?? this.inputFill,
      inputFillDisabled: inputFillDisabled ?? this.inputFillDisabled,
      fieldFocusRim: fieldFocusRim ?? this.fieldFocusRim,
      skeleton: skeleton ?? this.skeleton,
      cardShadow: cardShadow ?? this.cardShadow,
      barSeparator: barSeparator ?? this.barSeparator,
      messageIncoming: messageIncoming ?? this.messageIncoming,
      onMessageIncoming: onMessageIncoming ?? this.onMessageIncoming,
      messageOutgoing: messageOutgoing ?? this.messageOutgoing,
      onMessageOutgoing: onMessageOutgoing ?? this.onMessageOutgoing,
      notificationUnread: notificationUnread ?? this.notificationUnread,
      presenceOnline: presenceOnline ?? this.presenceOnline,
      unreadIndicator: unreadIndicator ?? this.unreadIndicator,
      swipeDestructive: swipeDestructive ?? this.swipeDestructive,
      swipeFavorite: swipeFavorite ?? this.swipeFavorite,
      destructiveInk: destructiveInk ?? this.destructiveInk,
      surfaceInset: surfaceInset ?? this.surfaceInset,
      ctaFill: ctaFill ?? this.ctaFill,
      onCtaFill: onCtaFill ?? this.onCtaFill,
      brandSurface: brandSurface ?? this.brandSurface,
      lineSubtle: lineSubtle ?? this.lineSubtle,
      lineDefault: lineDefault ?? this.lineDefault,
      lineStrong: lineStrong ?? this.lineStrong,
      lineInteractive: lineInteractive ?? this.lineInteractive,
      controlInk: controlInk ?? this.controlInk,
      controlOutline: controlOutline ?? this.controlOutline,
      iconTile: iconTile ?? this.iconTile,
      iconInk: iconInk ?? this.iconInk,
      reactionLike: reactionLike ?? this.reactionLike,
      heroSurfaceStart: heroSurfaceStart ?? this.heroSurfaceStart,
      heroSurfaceEnd: heroSurfaceEnd ?? this.heroSurfaceEnd,
      onHeroSurface: onHeroSurface ?? this.onHeroSurface,
      mediaSurface: mediaSurface ?? this.mediaSurface,
      onMediaSurface: onMediaSurface ?? this.onMediaSurface,
      uploadZoneFill: uploadZoneFill ?? this.uploadZoneFill,
      uploadZoneBorder: uploadZoneBorder ?? this.uploadZoneBorder,
      logoTile: logoTile ?? this.logoTile,
      avatarPalette: avatarPalette ?? this.avatarPalette,
    );
  }

  /// Interpolates between two token sets.
  ///
  /// Flutter calls this while animating a theme change. **A field omitted here
  /// throws at runtime during that animation, not at compile time** — which is
  /// why `semantic_tokens_test.dart` asserts every field is non-null at
  /// `t = 0.5`. Add a field to `copyWith`, to `lerp`, and to that test together.
  @override
  SyncUpSemantics lerp(ThemeExtension<SyncUpSemantics>? other, double t) {
    if (other is! SyncUpSemantics) return this;
    return SyncUpSemantics(
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      inputFillDisabled:
          Color.lerp(inputFillDisabled, other.inputFillDisabled, t)!,
      fieldFocusRim: Color.lerp(fieldFocusRim, other.fieldFocusRim, t)!,
      skeleton: Color.lerp(skeleton, other.skeleton, t)!,
      // `BoxShadow.lerpList` handles lists of different lengths by fading the
      // missing entries out, which is exactly what is needed between the light
      // shadow and dark's empty list.
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      barSeparator: Color.lerp(barSeparator, other.barSeparator, t)!,
      messageIncoming: Color.lerp(messageIncoming, other.messageIncoming, t)!,
      onMessageIncoming:
          Color.lerp(onMessageIncoming, other.onMessageIncoming, t)!,
      messageOutgoing: Color.lerp(messageOutgoing, other.messageOutgoing, t)!,
      onMessageOutgoing:
          Color.lerp(onMessageOutgoing, other.onMessageOutgoing, t)!,
      notificationUnread:
          Color.lerp(notificationUnread, other.notificationUnread, t)!,
      presenceOnline: Color.lerp(presenceOnline, other.presenceOnline, t)!,
      unreadIndicator: Color.lerp(unreadIndicator, other.unreadIndicator, t)!,
      swipeDestructive:
          Color.lerp(swipeDestructive, other.swipeDestructive, t)!,
      swipeFavorite: Color.lerp(swipeFavorite, other.swipeFavorite, t)!,
      destructiveInk: Color.lerp(destructiveInk, other.destructiveInk, t)!,
      surfaceInset: Color.lerp(surfaceInset, other.surfaceInset, t)!,
      ctaFill: Color.lerp(ctaFill, other.ctaFill, t)!,
      onCtaFill: Color.lerp(onCtaFill, other.onCtaFill, t)!,
      brandSurface: Color.lerp(brandSurface, other.brandSurface, t)!,
      lineSubtle: Color.lerp(lineSubtle, other.lineSubtle, t)!,
      lineDefault: Color.lerp(lineDefault, other.lineDefault, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      lineInteractive: Color.lerp(lineInteractive, other.lineInteractive, t)!,
      controlInk: Color.lerp(controlInk, other.controlInk, t)!,
      controlOutline: Color.lerp(controlOutline, other.controlOutline, t)!,
      iconTile: Color.lerp(iconTile, other.iconTile, t)!,
      iconInk: Color.lerp(iconInk, other.iconInk, t)!,
      reactionLike: Color.lerp(reactionLike, other.reactionLike, t)!,
      heroSurfaceStart:
          Color.lerp(heroSurfaceStart, other.heroSurfaceStart, t)!,
      heroSurfaceEnd: Color.lerp(heroSurfaceEnd, other.heroSurfaceEnd, t)!,
      onHeroSurface: Color.lerp(onHeroSurface, other.onHeroSurface, t)!,
      mediaSurface: Color.lerp(mediaSurface, other.mediaSurface, t)!,
      onMediaSurface: Color.lerp(onMediaSurface, other.onMediaSurface, t)!,
      uploadZoneFill: Color.lerp(uploadZoneFill, other.uploadZoneFill, t)!,
      uploadZoneBorder:
          Color.lerp(uploadZoneBorder, other.uploadZoneBorder, t)!,
      logoTile: Color.lerp(logoTile, other.logoTile, t)!,
      // Index-wise lerp. Both ramps are the same length by construction; the
      // guard keeps a mismatch from throwing mid-animation.
      avatarPalette: _lerpPalette(avatarPalette, other.avatarPalette, t),
    );
  }

  static List<Color> _lerpPalette(List<Color> a, List<Color> b, double t) {
    if (a.length != b.length) return t < 0.5 ? a : b;
    return <Color>[
      for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
    ];
  }
}
