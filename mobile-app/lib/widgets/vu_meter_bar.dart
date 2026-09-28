import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme.dart';

class VuMeterBar extends StatefulWidget {
  final bool active;
  final bool isMuted;
  final double? manualLevelL;
  final double? manualLevelR;
  final String title;

  const VuMeterBar({
    Key? key,
    this.active = true,
    this.isMuted = false,
    this.manualLevelL,
    this.manualLevelR,
    this.title = 'AUDIO STEREO TRUE PEAK',
  }) : super(key: key);

  @override
  State<VuMeterBar> createState() => _VuMeterBarState();
}

class _VuMeterBarState extends State<VuMeterBar> {
  Timer? _ticker;
  final Random _rng = Random();

  double _levelL = 0.0;
  double _levelR = 0.0;
  double _peakHoldL = 0.0;
  double _peakHoldR = 0.0;
  int _peakHoldTimerL = 0;
  int _peakHoldTimerR = 0;
  bool _isClipped = false;
  int _clipHoldTimer = 0;

  // Ballistics state
  double _targetL = 0.0;
  double _targetR = 0.0;
  double _rhythmPhase = 0.0;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(VuMeterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.isMuted != widget.isMuted) {
      if (!widget.active || widget.isMuted) {
        _targetL = 0.0;
        _targetR = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!mounted) return;
      _updateBallistics();
    });
  }

  void _updateBallistics() {
    // If manual levels are passed, use them directly
    if (widget.manualLevelL != null && widget.manualLevelR != null) {
      setState(() {
        _levelL = widget.manualLevelL!.clamp(0.0, 1.0);
        _levelR = widget.manualLevelR!.clamp(0.0, 1.0);
        _isClipped = _levelL > 0.96 || _levelR > 0.96;
      });
      return;
    }

    // If inactive (offline/paused), decay smoothly to zero
    if (!widget.active) {
      setState(() {
        _levelL = max(0.0, _levelL * 0.78);
        _levelR = max(0.0, _levelR * 0.78);
        _peakHoldL = max(0.0, _peakHoldL * 0.85);
        _peakHoldR = max(0.0, _peakHoldR * 0.85);
        _isClipped = false;
      });
      return;
    }

    // Realistic Broadcast Audio Simulation (EBU R128 speech & music dynamics)
    _rhythmPhase += 0.08;
    if (_rhythmPhase > 2 * pi) _rhythmPhase -= 2 * pi;

    // Cadence generator: combines slow breath/phrase wave with fast rhythmic accents
    final cadence = 0.55 +
        0.20 * sin(_rhythmPhase) +
        0.12 * sin(_rhythmPhase * 2.7) +
        0.08 * sin(_rhythmPhase * 4.3);

    // Occasional loud hit/peak (e.g. presenter emphasis or music beat)
    final bool isAccent = _rng.nextDouble() < 0.12;
    final double accentBoost = isAccent ? 0.22 * _rng.nextDouble() : 0.0;

    // Occasional brief pause between words (breathing room)
    final bool isPause = _rng.nextDouble() < 0.05;
    final double pauseDamping = isPause ? 0.4 : 1.0;

    final double baseLevel = ((cadence + accentBoost) * pauseDamping).clamp(0.20, 0.98);

    // Stereo separation: Common mono signal + subtle L/R stereo variance
    final double stereoSpread = (_rng.nextDouble() - 0.5) * 0.14;
    _targetL = (baseLevel + stereoSpread).clamp(0.05, 0.98);
    _targetR = (baseLevel - stereoSpread).clamp(0.05, 0.98);

    // Broadcast Ballistics: Fast attack (~15ms), smooth logarithmic decay (~300ms)
    if (_targetL > _levelL) {
      _levelL += (_targetL - _levelL) * 0.70; // Fast attack
    } else {
      _levelL -= (_levelL - _targetL) * 0.16; // Smooth decay
    }

    if (_targetR > _levelR) {
      _levelR += (_targetR - _levelR) * 0.70;
    } else {
      _levelR -= (_levelR - _targetR) * 0.16;
    }

    // True Peak Hold with 1.2s retention (approx 36 ticks at 33ms)
    if (_levelL > _peakHoldL) {
      _peakHoldL = _levelL;
      _peakHoldTimerL = 36;
    } else if (_peakHoldTimerL > 0) {
      _peakHoldTimerL--;
    } else {
      _peakHoldL = max(_levelL, _peakHoldL - 0.02);
    }

    if (_levelR > _peakHoldR) {
      _peakHoldR = _levelR;
      _peakHoldTimerR = 36;
    } else if (_peakHoldTimerR > 0) {
      _peakHoldTimerR--;
    } else {
      _peakHoldR = max(_levelR, _peakHoldR - 0.02);
    }

    // Clip Detection
    if (_levelL > 0.95 || _levelR > 0.95) {
      _isClipped = true;
      _clipHoldTimer = 25; // Hold CLIP indicator for ~0.8s
    } else if (_clipHoldTimer > 0) {
      _clipHoldTimer--;
    } else {
      _isClipped = false;
    }

    setState(() {});
  }

  String _formatDbfs() {
    if (!widget.active) return '-∞ dBFS';
    if (_isClipped) return 'PECAH! (CLIP)';
    final maxLevel = max(_levelL, _levelR);
    if (maxLevel <= 0.01) return '-∞ dBFS';
    // Map 0.0-1.0 to dBFS: 1.0 -> 0 dBFS, 0.5 -> -18 dBFS, 0.1 -> -40 dBFS
    final dbfs = 20 * (log(maxLevel) / ln10);
    final text = '${dbfs.toStringAsFixed(1)} dBFS';
    return widget.isMuted ? '$text (SPK MUTE)' : text;
  }

  Widget _buildChannelBar(String label, double level, double peakHold) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            label,
            style: const TextStyle(
              color: MakasnaTheme.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              // Background track
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B101B),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
              ),

              // Active VU Level Bar with Broadcast Gradient
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: level.clamp(0.0, 1.0),
                  child: Container(
                    height: 12,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF10B981), // Green (-inf to -18 dBFS)
                          Color(0xFF22C55E),
                          Color(0xFFF59E0B), // Amber (-18 to -6 dBFS)
                          Color(0xFFEF4444), // Red (-6 to 0 dBFS)
                        ],
                        stops: [0.0, 0.65, 0.85, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // Peak Hold Tick Line
              if (peakHold > 0.05 && widget.active && !widget.isMuted)
                Positioned(
                  left: 0,
                  right: 0,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: peakHold.clamp(0.0, 1.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 2,
                        height: 14,
                        decoration: BoxDecoration(
                          color: peakHold > 0.88 ? Colors.redAccent : Colors.white,
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: const [
                            BoxShadow(color: Colors.white70, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxLevel = max(_levelL, _levelR);
    final isAmberZone = maxLevel > 0.82 && !_isClipped;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MakasnaTheme.panelElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isClipped
              ? MakasnaTheme.red.withOpacity(0.6)
              : MakasnaTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: widget.active && !widget.isMuted
                          ? MakasnaTheme.green
                          : Colors.grey[700],
                      shape: BoxShape.circle,
                      boxShadow: widget.active && !widget.isMuted
                          ? [
                              BoxShadow(
                                color: MakasnaTheme.green.withOpacity(0.5),
                                blurRadius: 5,
                              )
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: MakasnaTheme.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),

              // Real-time Peak dBFS readout badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: _isClipped
                      ? MakasnaTheme.red
                      : (isAmberZone
                          ? const Color(0x33F59E0B)
                          : const Color(0xFF1E293B)),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _isClipped
                        ? Colors.redAccent
                        : (isAmberZone
                            ? MakasnaTheme.amber
                            : Colors.transparent),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  widget.isMuted ? 'MUTED' : _formatDbfs(),
                  style: TextStyle(
                    color: _isClipped
                        ? Colors.white
                        : (isAmberZone
                            ? MakasnaTheme.amber
                            : (widget.isMuted
                                ? MakasnaTheme.textDim
                                : MakasnaTheme.cyan)),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildChannelBar('CH1', _levelL, _peakHoldL),
          const SizedBox(height: 5),
          _buildChannelBar('CH2', _levelR, _peakHoldR),
          const SizedBox(height: 6),

          // Scale Markings: -40, -20, -12, -6, 0 dBFS
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('-40', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                Text('-24', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                Text('-18', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                Text('-12', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                Text('-6', style: TextStyle(color: MakasnaTheme.amber, fontSize: 8, fontFamily: 'monospace')),
                Text('0 dB', style: TextStyle(color: MakasnaTheme.red, fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
