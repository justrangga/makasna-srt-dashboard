import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../core/theme.dart';
import '../providers/gateway_provider.dart';

class BroadcastVideoPlayer extends StatefulWidget {
  final String streamId;
  final String? customUrl;
  final double aspectRatio;
  final bool autoPlay;
  final bool showControls;
  final bool defaultMuted;
  final bool isFullscreen;
  final ValueChanged<bool>? onPlayStateChanged;
  final ValueChanged<bool>? onMuteStateChanged;

  const BroadcastVideoPlayer({
    Key? key,
    required this.streamId,
    this.customUrl,
    this.aspectRatio = 16 / 9,
    this.autoPlay = true,
    this.showControls = true,
    this.defaultMuted = true,
    this.isFullscreen = false,
    this.onPlayStateChanged,
    this.onMuteStateChanged,
  }) : super(key: key);

  @override
  State<BroadcastVideoPlayer> createState() => _BroadcastVideoPlayerState();
}

class _BroadcastVideoPlayerState extends State<BroadcastVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String? _errorMessage;
  late bool _isMuted;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  String _activeUrl = '';
  List<String> _candidateUrls = [];
  int _currentCandidateIndex = 0;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.defaultMuted;
    _startHideTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveUrlAndInit();
  }

  @override
  void didUpdateWidget(BroadcastVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamId != widget.streamId || oldWidget.customUrl != widget.customUrl) {
      _resolveUrlAndInit(force: true);
    }
  }

  void _resolveUrlAndInit({bool force = false}) {
    final gateway = context.read<GatewayProvider>();
    if (widget.customUrl != null && widget.customUrl!.isNotEmpty) {
      _candidateUrls = [widget.customUrl!];
    } else {
      _candidateUrls = gateway.config.getHlsCandidates(widget.streamId);
      if (_candidateUrls.isEmpty) {
        _candidateUrls = [gateway.config.buildHlsUrl(widget.streamId)];
      }
    }

    if (force || _activeUrl.isEmpty || !_candidateUrls.contains(_activeUrl)) {
      _currentCandidateIndex = 0;
      _activeUrl = _candidateUrls[_currentCandidateIndex];
      _initController();
    }
  }

  void _switchNextCandidate() {
    if (_candidateUrls.length <= 1) return;
    _currentCandidateIndex = (_currentCandidateIndex + 1) % _candidateUrls.length;
    _activeUrl = _candidateUrls[_currentCandidateIndex];
    _initController();
  }

  Future<void> _initController() async {
    _reconnectTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    await _controller?.dispose();
    _controller = null;

    if (!mounted || _activeUrl.isEmpty) return;

    setState(() {
      _isInitialized = false;
      _hasError = false;
      _errorMessage = null;
      _isBuffering = true;
    });

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(_activeUrl),
        formatHint: VideoFormat.hls,
        httpHeaders: const {
          'User-Agent': 'MakasnaRemote/1.2.0 (Android Broadcast Player)',
          'Accept': '*/*',
        },
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );

      _controller = controller;
      controller.addListener(_onControllerUpdate);

      await controller.initialize();

      if (!mounted) return;

      // Start muted to comply with Android auto-play policies
      await controller.setVolume(0.0);
      await controller.setLooping(true);

      if (widget.autoPlay) {
        await controller.play();
      }

      if (!_isMuted) {
        await controller.setVolume(1.0);
      }

      widget.onPlayStateChanged?.call(controller.value.isPlaying);
      widget.onMuteStateChanged?.call(_isMuted);

      setState(() {
        _isInitialized = true;
        _isBuffering = false;
        _hasError = false;
        _retryCount = 0;
      });
    } catch (e) {
      if (!mounted) return;

      // Try next candidate URL if available
      if (_currentCandidateIndex < _candidateUrls.length - 1) {
        _currentCandidateIndex++;
        _activeUrl = _candidateUrls[_currentCandidateIndex];
        _initController();
        return;
      }

      _retryCount++;
      final errSummary = e.toString().replaceAll('Exception: ', '').split('\n').first;
      setState(() {
        _isInitialized = false;
        _isBuffering = false;
        _hasError = true;
        _errorMessage = 'Gagal memutar: $errSummary ($_retryCount)';
      });

      _reconnectTimer = Timer(const Duration(milliseconds: 3000), () {
        if (mounted) {
          _currentCandidateIndex = 0;
          _activeUrl = _candidateUrls.isNotEmpty ? _candidateUrls[0] : '';
          _initController();
        }
      });
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;

    final val = _controller!.value;
    final buffering = val.isBuffering;
    final err = val.hasError;

    if (buffering != _isBuffering || err != _hasError) {
      setState(() {
        _isBuffering = buffering;
        _hasError = err;
        if (err) {
          _errorMessage = val.errorDescription;
          // Auto recover on playback error
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(const Duration(seconds: 3), _initController);
        }
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        widget.onPlayStateChanged?.call(false);
      } else {
        _controller!.play();
        widget.onPlayStateChanged?.call(true);
      }
    });
    _resetHideTimer();
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
      widget.onMuteStateChanged?.call(_isMuted);
    });
    _resetHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _resetHideTimer() {
    setState(() => _controlsVisible = true);
    _startHideTimer();
  }

  void _openFullscreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenPlayerView(
          streamId: widget.streamId,
          activeUrl: _activeUrl,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _reconnectTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_controlsVisible) {
          setState(() => _controlsVisible = false);
          _hideTimer?.cancel();
        } else {
          _resetHideTimer();
        }
      },
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: widget.isFullscreen ? BorderRadius.zero : BorderRadius.circular(10),
            border: widget.isFullscreen
                ? null
                : Border.all(color: MakasnaTheme.cyan.withOpacity(0.5), width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Video Layer
              if (_controller != null && _isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio > 0
                        ? _controller!.value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else
                _buildStandbySlate(),

              // 2. Buffering Spinner
              if (_isBuffering && !_hasError)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: MakasnaTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: MakasnaTheme.cyan),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'BUFFERING...',
                          style: TextStyle(
                            color: MakasnaTheme.cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 3. Top OSD Bar (Tally & Resolution)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Live Tally Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _isInitialized ? MakasnaTheme.red : Colors.grey[800],
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: _isInitialized
                              ? [BoxShadow(color: MakasnaTheme.red.withOpacity(0.4), blurRadius: 6)]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _isInitialized ? Colors.white : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isInitialized ? 'LIVE' : 'STANDBY',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Resolution & FPS Info
                      if (_isInitialized && _controller != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            '${_controller!.value.size.width.toInt()}x${_controller!.value.size.height.toInt()} · fMP4',
                            style: const TextStyle(
                              color: MakasnaTheme.cyan,
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      // Fullscreen / Refresh buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Re-sync Live Edge',
                            onPressed: () => _initController(),
                          ),
                          if (!widget.isFullscreen) ...[
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(Icons.fullscreen, size: 20, color: Colors.white),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Fullscreen View',
                              onPressed: _openFullscreen,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Bottom Controls Overlay
              if (widget.showControls)
                Positioned(
                  bottom: 6,
                  left: 8,
                  right: 8,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          // Play / Pause
                          InkWell(
                            onTap: _togglePlayPause,
                            child: Icon(
                              _controller != null && _controller!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: MakasnaTheme.cyan,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Mute / Unmute
                          InkWell(
                            onTap: _toggleMute,
                            child: Icon(
                              _isMuted ? Icons.volume_off : Icons.volume_up,
                              color: _isMuted ? MakasnaTheme.amber : MakasnaTheme.green,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Stream ID text
                          Expanded(
                            child: Text(
                              widget.streamId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // Port / Route Tag with tap to toggle
                          InkWell(
                            onTap: _candidateUrls.length > 1 ? _switchNextCandidate : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: _activeUrl.contains(':8888')
                                    ? const Color(0x333B82F6)
                                    : const Color(0x3310B981),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: _activeUrl.contains(':8888')
                                      ? MakasnaTheme.blue
                                      : MakasnaTheme.green,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                _activeUrl.contains(':8888')
                                    ? (_activeUrl.contains('video1_stream') ? 'DIRECT V-ONLY' : 'DIRECT 8888')
                                    : (_activeUrl.contains('video1_stream') ? 'PROXY V-ONLY' : 'PROXY HLS'),
                                style: TextStyle(
                                  color: _activeUrl.contains(':8888')
                                      ? MakasnaTheme.blueLight
                                      : MakasnaTheme.green,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandbySlate() {
    return Container(
      color: const Color(0xFF07090E),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle SMPTE Color Bars header stripe
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 4,
            child: Row(
              children: const [
                Expanded(child: ColoredBox(color: Color(0xFFC0C0C0))),
                Expanded(child: ColoredBox(color: Color(0xFFC0C000))),
                Expanded(child: ColoredBox(color: Color(0xFF00C0C0))),
                Expanded(child: ColoredBox(color: Color(0xFF00C000))),
                Expanded(child: ColoredBox(color: Color(0xFFC000C0))),
                Expanded(child: ColoredBox(color: Color(0xFFC00000))),
                Expanded(child: ColoredBox(color: Color(0xFF0000C0))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _hasError ? Icons.cell_tower : Icons.live_tv,
                  size: 34,
                  color: _hasError ? MakasnaTheme.amber : MakasnaTheme.cyan,
                ),
                const SizedBox(height: 6),
                Text(
                  'FEED: ${widget.streamId}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    letterSpacing: 0.8,
                  ),
                ),
                if (_activeUrl.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _activeUrl,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 8.5,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _hasError
                      ? (_errorMessage ?? 'Menunggu sinyal ingest...')
                      : 'Memuat feed video broadcast...',
                  style: TextStyle(
                    color: _hasError ? MakasnaTheme.amber : MakasnaTheme.textDim,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                if (_candidateUrls.length > 1) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MakasnaTheme.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _switchNextCandidate,
                        icon: const Icon(Icons.swap_horiz, size: 12),
                        label: Text(
                          'Coba Jalur Lain (${_currentCandidateIndex + 1}/${_candidateUrls.length})',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MakasnaTheme.cyan,
                          side: const BorderSide(color: MakasnaTheme.cyan),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _initController(),
                        icon: const Icon(Icons.refresh, size: 12),
                        label: const Text('Muat Ulang', style: TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _hasError ? MakasnaTheme.amber : MakasnaTheme.cyan,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dedicated Fullscreen Landscape / Portrait Monitor
class _FullscreenPlayerView extends StatefulWidget {
  final String streamId;
  final String activeUrl;

  const _FullscreenPlayerView({
    Key? key,
    required this.streamId,
    required this.activeUrl,
  }) : super(key: key);

  @override
  State<_FullscreenPlayerView> createState() => _FullscreenPlayerViewState();
}

class _FullscreenPlayerViewState extends State<_FullscreenPlayerView> {
  @override
  void initState() {
    super.initState();
    // Allow auto-rotation for fullscreen inspection
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore normal orientation
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: BroadcastVideoPlayer(
              streamId: widget.streamId,
              customUrl: widget.activeUrl,
              aspectRatio: 16 / 9,
              autoPlay: true,
              showControls: true,
              defaultMuted: false,
              isFullscreen: true,
            ),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
