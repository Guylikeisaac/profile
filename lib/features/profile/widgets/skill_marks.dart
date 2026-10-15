import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// A skill's or tool's visual identity: its brand hue and, when one ships in
/// Font Awesome, its mark.
typedef SkillMark = ({Color hue, FaIconData? icon});

/// Known skills and tools, keyed lowercase. Brand hues are the products' own;
/// practices (Prototyping, Analytics…) get a hue that suits them and no mark.
const Map<String, SkillMark> _marks = {
  // Languages & frameworks
  'react': (hue: Color(0xFF61DAFB), icon: FontAwesomeIcons.react),
  'node.js': (hue: Color(0xFF8CC84B), icon: FontAwesomeIcons.nodeJs),
  'node': (hue: Color(0xFF8CC84B), icon: FontAwesomeIcons.nodeJs),
  'javascript': (hue: Color(0xFFF7DF1E), icon: FontAwesomeIcons.js),
  'typescript': (hue: Color(0xFF3178C6), icon: null),
  'python': (hue: Color(0xFF4B8BBE), icon: FontAwesomeIcons.python),
  'go': (hue: Color(0xFF00ADD8), icon: FontAwesomeIcons.golang),
  'java': (hue: Color(0xFFED8B00), icon: FontAwesomeIcons.java),
  'rust': (hue: Color(0xFFDEA584), icon: FontAwesomeIcons.rust),
  'angular': (hue: Color(0xFFDD0031), icon: FontAwesomeIcons.angular),
  'vue': (hue: Color(0xFF42B883), icon: FontAwesomeIcons.vuejs),
  'flutter': (hue: Color(0xFF54C5F8), icon: null),
  'html': (hue: Color(0xFFE34F26), icon: FontAwesomeIcons.html5),
  'html/css': (hue: Color(0xFFE34F26), icon: FontAwesomeIcons.html5),
  'css': (hue: Color(0xFF2965F1), icon: FontAwesomeIcons.css3Alt),
  // Platforms & tools
  'docker': (hue: Color(0xFF2496ED), icon: FontAwesomeIcons.docker),
  'aws': (hue: Color(0xFFFF9900), icon: FontAwesomeIcons.aws),
  'git': (hue: Color(0xFFF05032), icon: FontAwesomeIcons.gitAlt),
  'android': (hue: Color(0xFF3DDC84), icon: FontAwesomeIcons.android),
  'apple': (hue: Color(0xFFE6E6E6), icon: FontAwesomeIcons.apple),
  'ios': (hue: Color(0xFFE6E6E6), icon: FontAwesomeIcons.apple),
  'storybook': (hue: Color(0xFFFF4785), icon: null),
  'lottie': (hue: Color(0xFF00DDB3), icon: null),
  // Design
  'figma': (hue: Color(0xFFF24E1E), icon: FontAwesomeIcons.figma),
  'framer': (hue: Color(0xFF0099FF), icon: null),
  'sketch': (hue: Color(0xFFF7B500), icon: FontAwesomeIcons.sketch),
  'dribbble': (hue: Color(0xFFEA4C89), icon: FontAwesomeIcons.dribbble),
  'prototyping': (hue: Color(0xFFA78BFA), icon: null),
  'interaction design': (hue: Color(0xFFF472B6), icon: null),
  'motion': (hue: Color(0xFFFB923C), icon: null),
  'design systems': (hue: Color(0xFF818CF8), icon: null),
  // Research
  'usability testing': (hue: Color(0xFF34D399), icon: null),
  'interviews': (hue: Color(0xFF2DD4BF), icon: null),
  'a/b testing': (hue: Color(0xFF38BDF8), icon: null),
  'analytics': (hue: Color(0xFFFBBF24), icon: null),
  // Leadership
  'mentoring': (hue: Color(0xFFF87171), icon: null),
  'workshops': (hue: Color(0xFFFACC15), icon: null),
  'stakeholder mgmt': (hue: Color(0xFFC084FC), icon: null),
};

/// Hues for skills with no entry above, picked stably from the name so the
/// same skill is always the same colour.
const List<Color> _fallbackHues = [
  Color(0xFF60A5FA),
  Color(0xFF34D399),
  Color(0xFFF472B6),
  Color(0xFFFBBF24),
  Color(0xFFA78BFA),
  Color(0xFF2DD4BF),
  Color(0xFFFB923C),
  Color(0xFFF87171),
];

/// The mark for [name]: its known brand hue and icon, or a stable hue and no
/// icon when it is not one we know.
SkillMark skillMarkFor(String name) {
  final key = name.trim().toLowerCase();
  final known = _marks[key];
  if (known != null) return known;
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return (hue: _fallbackHues[h % _fallbackHues.length], icon: null);
}

/// A skill as a tinted chip: a wash of its hue, a faint rim of it, its mark
/// when it has one, and the name in a lifted shade of the hue.
class SkillColorChip extends StatelessWidget {
  const SkillColorChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final mark = skillMarkFor(label);
    final ink = Color.lerp(mark.hue, Colors.white, 0.25)!;
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: mark.hue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: mark.hue.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mark.icon != null) ...[
            FaIcon(mark.icon, size: 12, color: mark.hue),
            const SizedBox(width: 6),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: mark.hue, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// A skill or tool as a small square tile with its mark (or its initials
/// when it has none), tinted with its hue. The name is the tooltip.
class SkillMarkTile extends StatelessWidget {
  const SkillMarkTile({super.key, required this.name, this.size = 22});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mark = skillMarkFor(name);
    final trimmed = name.trim();
    final initials = trimmed.isEmpty
        ? '?'
        : trimmed.substring(0, trimmed.length < 2 ? trimmed.length : 2);
    return Tooltip(
      message: name,
      child: Semantics(
        label: name,
        excludeSemantics: true,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mark.hue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(size * 0.28),
            border: Border.all(color: mark.hue.withValues(alpha: 0.4)),
          ),
          child: mark.icon != null
              ? FaIcon(mark.icon, size: size * 0.5, color: mark.hue)
              : Text(
                  initials,
                  style: TextStyle(
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w800,
                    color: mark.hue,
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}
