import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../core/theme/theme_context_ext.dart';

/// Full-screen player for a profile intro video.
///
/// Kept intentionally defensive: [video_player] is a native plugin, so its
/// [VideoPlayerController.initialize] can fail for two very different reasons —
///   1. the running app binary predates the plugin being added (a channel
///      "connection" error after a hot restart instead of a full rebuild), or
///   2. the media URL exists but can't actually be fetched/decoded (e.g. a
///      private object, an unsupported codec, or no network).
/// Both surface here as a graceful error state with a Retry, and the underlying
/// error is logged (not swallowed) so the real cause is visible in the console.
class IntroVideoPlayerScreen extends StatefulWidget {
  const IntroVideoPlayerScreen({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  State<IntroVideoPlayerScreen> createState() => _IntroVideoPlayerScreenState();
}

class _IntroVideoPlayerScreenState extends State<IntroVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _initializing = true;
  bool _muted = false;
  bool _showControls = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _initializing = true;
      _ready = false;
      _error = null;
    });

    // Dispose any previous controller (Retry path).
    await _controller?.dispose();

    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _initializing = false;
        _error = "This video link looks invalid, so it can't be played.";
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _initializing = false;
      });
      await controller.play();
      if (mounted) setState(() {});
    } catch (e, st) {
      // Surface, don't swallow: a channel/connection error here almost always
      // means the app was hot-restarted after adding the plugin instead of
      // being fully rebuilt. Any other error is a genuine playback failure.
      debugPrint('Intro video failed to initialize: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not play this video.';
      });
    }
  }

  void _togglePlayback() {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  void _replay() {
    final c = _controller;
    if (c == null || !_ready) return;
    c.seekTo(Duration.zero);
    c.play();
    setState(() {});
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    final topInset = MediaQuery.of(context).padding.top;
    return Scaffold(
      // Fixed in both themes: video is watched against black.
      backgroundColor: tokens.mediaSurface,
      body: Stack(
        children: [
          Positioned.fill(child: _body(context)),
          // Shared back button, over the video — a light-grey translucent chip.
          Positioned(
            top: topInset + 8,
            left: 12,
            child: AppBackButton(
              // Pushed with a plain Navigator route, so pop it directly.
              onTap: () => Navigator.of(context).maybePop(),
              // The chip's fill stays a light scrim (the white glyph is what
              // carries the affordance, at 21:1), but the *border* is the
              // control's visible boundary and has to clear WCAG 1.4.11's 3:1
              // on its own — 0.28 measured 2.26:1 over the black media ground.
              backgroundColor: tokens.onMediaSurface.withValues(alpha: 0.16),
              borderColor: tokens.onMediaSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final tokens = context.tokensOrDefault;
    if (_initializing) {
      return Center(
        child: CircularProgressIndicator(color: tokens.onMediaSurface),
      );
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final controller = _controller!;
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0
                  ? 16 / 9
                  : controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          // Controls fade in/out on tap.
          AnimatedOpacity(
            opacity: _showControls ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: _Controls(
                controller: controller,
                muted: _muted,
                onPlayPause: _togglePlayback,
                onReplay: _replay,
                onToggleMute: _toggleMute,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The play/pause + scrubber + time + replay/mute overlay.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.muted,
    required this.onPlayPause,
    required this.onReplay,
    required this.onToggleMute,
  });

  final VideoPlayerController controller;
  final bool muted;
  final VoidCallback onPlayPause;
  final VoidCallback onReplay;
  final VoidCallback onToggleMute;

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Stack(
          children: [
            // Dim scrim so white controls read over any frame.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: tokens.mediaSurface.withValues(alpha: 0.2)),
              ),
            ),
            // Center play / pause.
            Center(
              child: GestureDetector(
                onTap: onPlayPause,
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: tokens.mediaSurface.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    value.isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                    size: 40,
                    color: tokens.onMediaSurface,
                  ),
                ),
              ),
            ),
            // Bottom bar: time, scrubber, replay + mute.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        // Three levels that stay distinguishable from each
                        // other *and* from the media behind them. The unplayed
                        // track was 0.30, which measured 2.45:1 over black —
                        // below the 3:1 floor for a meaningful control.
                        colors: VideoProgressColors(
                          playedColor: tokens.onMediaSurface,
                          bufferedColor:
                              tokens.onMediaSurface.withValues(alpha: 0.60),
                          backgroundColor:
                              tokens.onMediaSurface.withValues(alpha: 0.38),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${_fmt(value.position)} / ${_fmt(value.duration)}',
                            style: TextStyle(
                              color: tokens.onMediaSurface,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          _RoundControl(
                            icon: Icons.replay,
                            onTap: onReplay,
                            tooltip: 'Replay',
                          ),
                          const SizedBox(width: 10),
                          _RoundControl(
                            icon: muted ? Icons.volume_off : Icons.volume_up,
                            onTap: onToggleMute,
                            tooltip: muted ? 'Unmute' : 'Mute',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // A backing scrim, not the control indicator: the glyph below is
            // full-strength `onMediaSurface` (21:1 over the media ground), so
            // the control itself is well clear of the 3:1 minimum.
            color: tokens.onMediaSurface.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 19, color: tokens.onMediaSurface),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 44, color: tokens.onMediaSurface.withValues(alpha: 0.70)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.onMediaSurface, fontSize: 14.5),
            ),
            const SizedBox(height: 20),
            // The app's secondary button: charcoal glass reads on the black
            // player as it does on the page.
            AppButton.secondary(
              label: 'Retry',
              onPressed: onRetry,
              expand: false,
              size: AppButtonSize.compact,
            ),
          ],
        ),
      ),
    );
  }
}
