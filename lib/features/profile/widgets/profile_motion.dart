import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';

/// The profile's motion kit: entrance reveals, a count-up for numbers, a
/// pulsing status dot, a slowly turning avatar ring, a drawn hairline and a
/// loading shimmer.
///
/// The profile scrolls in a lazily-built list, so a section mounts as it
/// approaches the viewport — a mount-triggered [ProfileReveal] therefore
/// reads as a scroll reveal with no visibility tracking. Every piece collapses
/// to its final frame under reduced motion ([AppMotion.reducedMotion]).

/// Fades, lifts and slightly scales [child] into place once, [delay] after it
/// mounts.
class ProfileReveal extends StatefulWidget {
  const ProfileReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 620),
    this.offset = 28,
    this.scale = 0.97,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// How far below its resting place the child starts, in logical pixels.
  final double offset;

  /// The scale the child starts at.
  final double scale;

  @override
  State<ProfileReveal> createState() => _ProfileRevealState();
}

class _ProfileRevealState extends State<ProfileReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOutQuart);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reducedMotion(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final t = _t.value;
        return Opacity(
          opacity: Curves.easeOut.transform(t.clamp(0.0, 1.0)),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: Transform.scale(
              scale: widget.scale + (1 - widget.scale) * t,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Counts the numeric part of [value] up from zero ("248" → 0…248,
/// "5+" → 0…5 then "+", "1.2K" → 0.0…1.2 then "K"). Non-numeric values are
/// shown as they are.
class ProfileCountUp extends StatefulWidget {
  const ProfileCountUp({
    super.key,
    required this.value,
    required this.style,
    this.delay = const Duration(milliseconds: 250),
    this.duration = const Duration(milliseconds: 1400),
  });

  final String value;
  final TextStyle style;
  final Duration delay;
  final Duration duration;

  @override
  State<ProfileCountUp> createState() => _ProfileCountUpState();
}

class _ProfileCountUpState extends State<ProfileCountUp>
    with SingleTickerProviderStateMixin {
  static final RegExp _number = RegExp(r'^([^0-9]*)([0-9]+(?:\.[0-9]+)?)(.*)$');

  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOutExpo);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reducedMotion(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(ProfileCountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !AppMotion.reducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _number.firstMatch(widget.value);
    if (m == null) return Text(widget.value, style: widget.style, maxLines: 1);
    final raw = m.group(2)!;
    final target = double.parse(raw);
    final decimals = raw.contains('.') ? raw.split('.').last.length : 0;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) => Text(
        '${m.group(1)}${(target * _t.value).toStringAsFixed(decimals)}'
        '${m.group(3)}',
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A status dot with a ring that keeps expanding out of it and fading — a
/// live signal ("Open to Work").
class ProfilePulseDot extends StatefulWidget {
  const ProfilePulseDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  State<ProfilePulseDot> createState() => _ProfilePulseDotState();
}

class _ProfilePulseDotState extends State<ProfilePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reducedMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + t * 1.8,
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.55 * (1 - t)),
                  ),
                ),
              ),
              Container(
                width: s,
                height: s,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A thin ring whose bright arc slowly orbits [child] — the avatar's halo.
class ProfileOrbitRing extends StatefulWidget {
  const ProfileOrbitRing({
    super.key,
    required this.child,
    required this.size,
    this.color = Colors.white,
    this.width = 1.6,
  });

  final Widget child;
  final double size;
  final Color color;
  final double width;

  @override
  State<ProfileOrbitRing> createState() => _ProfileOrbitRingState();
}

class _ProfileOrbitRingState extends State<ProfileOrbitRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reducedMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  size: Size.square(widget.size),
                  painter: _OrbitPainter(
                    turn: _c.value,
                    color: widget.color,
                    width: widget.width,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({
    required this.turn,
    required this.color,
    required this.width,
  });

  final double turn;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(width / 2);
    // A dim full ring…
    canvas.drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color.withValues(alpha: 0.28),
    );
    // …with a bright comet arc travelling round it.
    final start = turn * 2 * math.pi;
    canvas.drawArc(
      r,
      start,
      math.pi * 0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 0.6
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 0.9,
          colors: [color.withValues(alpha: 0), color],
          transform: GradientRotation(start),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.turn != turn || old.color != color || old.width != width;
}

/// A 1px line that draws itself from the left edge across, once, on mount.
class ProfileDrawnLine extends StatefulWidget {
  const ProfileDrawnLine({super.key, required this.color, this.delay});

  final Color color;
  final Duration? delay;

  @override
  State<ProfileDrawnLine> createState() => _ProfileDrawnLineState();
}

class _ProfileDrawnLineState extends State<ProfileDrawnLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reducedMotion(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay ?? const Duration(milliseconds: 80),
          () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: Curves.easeInOutCubic.transform(_c.value),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [widget.color, widget.color.withValues(alpha: 0.15)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A moving highlight over [child] — the loading skeleton's shimmer.
class ProfileShimmer extends StatefulWidget {
  const ProfileShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<ProfileShimmer> createState() => _ProfileShimmerState();
}

class _ProfileShimmerState extends State<ProfileShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reducedMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final x = -1.5 + _c.value * 3;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 0.6, -0.3),
            end: Alignment(x + 0.6, 0.3),
            colors: const [
              Color(0xFF141414),
              Color(0xFF2A2A2A),
              Color(0xFF141414),
            ],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
