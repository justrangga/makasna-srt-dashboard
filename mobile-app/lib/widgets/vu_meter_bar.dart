import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme.dart';

enum MeterScale { dbfs, dbvu }

class VuMeterBar extends StatefulWidget {
  final bool active;
  final bool isMuted;
  final double? manualLevelL;
  final double? manualLevelR;
  final String title;
  final MeterScale defaultScale;
  final int defaultChannelCount;

  const VuMeterBar({
    Key? key,
    this.active = true,
    this.isMuted = false,
    this.manualLevelL,
    this.manualLevelR,
    this.title = 'AUDIO BROADCAST METERS',
    this.defaultScale = MeterScale.dbfs,
    this.defaultChannelCount = 2,
  }) : super(key: key);

  @override
  State<VuMeterBar> createState() => _VuMeterBarState();
}

class _VuMeterBarState extends State<VuMeterBar> {
  Timer? _ticker;
  final Random _rng = Random();

  late MeterScale _scale;
  late int _channelCount; // 2 or 4

  // Channel mapping: which SRT stream audio channel (1..8) maps to bar 0..3
  final List<int> _assignedChannels = [1, 2, 3, 4];

  // 4-Channel Dynamic Levels
  final List<double> _levels = [0.0, 0.0, 0.0, 0.0];
  final List<double> _peakHolds = [0.0, 0.0, 0.0, 0.0];
  final List<int> _peakHoldTimers = [0, 0, 0, 0];
  final List<double> _targets = [0.0, 0.0, 0.0, 0.0];

  bool _isClipped = false;
  int _clipHoldTimer = 0;
  double _rhythmPhase = 0.0;

  @override
  void initState() {
    super.initState();
    _scale = widget.defaultScale;
    _channelCount = widget.defaultChannelCount;
    _startAnimation();
  }

  @override
  void didUpdateWidget(VuMeterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.isMuted != widget.isMuted) {
      if (!widget.active || widget.isMuted) {
        for (int i = 0; i < 4; i++) {
          _targets[i] = 0.0;
        }
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
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted) return;
      _updateBallistics();
    });
  }

  void _updateBallistics() {
    // If manual levels are provided for stereo pair, use them for CH1 & CH2
    if (widget.manualLevelL != null && widget.manualLevelR != null) {
      setState(() {
        _levels[0] = widget.manualLevelL!.clamp(0.0, 1.0);
        _levels[1] = widget.manualLevelR!.clamp(0.0, 1.0);
        _levels[2] = (_levels[0] * 0.85).clamp(0.0, 1.0);
        _levels[3] = (_levels[1] * 0.82).clamp(0.0, 1.0);
        _isClipped = _levels[0] > 0.96 || _levels[1] > 0.96;
      });
      return;
    }

    // Inactive / Paused / Muted -> smooth logarithmic decay to zero
    if (!widget.active) {
      setState(() {
        for (int i = 0; i < 4; i++) {
          _levels[i] = max(0.0, _levels[i] * 0.78);
          _peakHolds[i] = max(0.0, _peakHolds[i] * 0.85);
        }
        _isClipped = false;
      });
      return;
    }

    // Dynamic Multi-Channel Broadcast Simulation (Speech + Music + Ambience)
    _rhythmPhase += 0.08;
    if (_rhythmPhase > 2 * pi) _rhythmPhase -= 2 * pi;

    final cadence = 0.54 +
        0.20 * sin(_rhythmPhase) +
        0.12 * sin(_rhythmPhase * 2.7) +
        0.08 * sin(_rhythmPhase * 4.3);

    final bool isAccent = _rng.nextDouble() < 0.12;
    final double accentBoost = isAccent ? 0.22 * _rng.nextDouble() : 0.0;
    final bool isPause = _rng.nextDouble() < 0.05;
    final double pauseDamping = isPause ? 0.40 : 1.0;

    final double mainBase = ((cadence + accentBoost) * pauseDamping).clamp(0.20, 0.98);

    // CH1 & CH2 (Primary Presenter / Program Stereo)
    final double spread12 = (_rng.nextDouble() - 0.5) * 0.14;
    _targets[0] = (mainBase + spread12).clamp(0.05, 0.98);
    _targets[1] = (mainBase - spread12).clamp(0.05, 0.98);

    // CH3 & CH4 (Secondary Feed / Guest / Audience Ambience)
    final double ambienceCadence = 0.35 + 0.15 * sin(_rhythmPhase * 1.8 + 1.2);
    final double spread34 = (_rng.nextDouble() - 0.5) * 0.10;
    _targets[2] = ((ambienceCadence + spread34) * pauseDamping).clamp(0.05, 0.92);
    _targets[3] = ((ambienceCadence - spread34) * pauseDamping).clamp(0.05, 0.92);

    bool anyClip = false;

    for (int i = 0; i < 4; i++) {
      // Broadcast Ballistics: Fast attack (~15ms), smooth decay (~300ms)
      if (_targets[i] > _levels[i]) {
        _levels[i] += (_targets[i] - _levels[i]) * 0.70;
      } else {
        _levels[i] -= (_levels[i] - _targets[i]) * 0.16;
      }

      // True Peak Hold (1.2s hold duration ~ 36 frames)
      if (_levels[i] > _peakHolds[i]) {
        _peakHolds[i] = _levels[i];
        _peakHoldTimers[i] = 36;
      } else if (_peakHoldTimers[i] > 0) {
        _peakHoldTimers[i]--;
      } else {
        _peakHolds[i] = max(_levels[i], _peakHolds[i] - 0.02);
      }

      if (_levels[i] > 0.95) anyClip = true;
    }

    if (anyClip) {
      _isClipped = true;
      _clipHoldTimer = 25;
    } else if (_clipHoldTimer > 0) {
      _clipHoldTimer--;
    } else {
      _isClipped = false;
    }

    setState(() {});
  }

  // Calculate dBFS or dBVU readout string
  String _formatLevelReadout() {
    if (!widget.active) return _scale == MeterScale.dbfs ? '-∞ dBFS' : '-∞ VU';
    if (_isClipped) return 'PECAH! (CLIP)';

    final double maxLevel = _levels.take(_channelCount).fold(0.0, (a, b) => max(a, b));
    if (maxLevel <= 0.01) return _scale == MeterScale.dbfs ? '-∞ dBFS' : '-∞ VU';

    // Linear amplitude 0.01..1.0 to dBFS (-40..0 dBFS)
    final dbfs = 20 * (log(maxLevel) / ln10);

    if (_scale == MeterScale.dbvu) {
      // Broadcast standard: -18 dBFS aligns with 0 VU
      final dbvu = dbfs + 18.0;
      final sign = dbvu >= 0 ? '+' : '';
      final text = '$sign${dbvu.toStringAsFixed(1)} VU';
      return widget.isMuted ? '$text (SPK MUTE)' : text;
    } else {
      final text = '${dbfs.toStringAsFixed(1)} dBFS';
      return widget.isMuted ? '$text (SPK MUTE)' : text;
    }
  }

  void _showChannelPicker(BuildContext context, int barIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MakasnaTheme.panelElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PILIH AUDIO CHANNEL UNTUK BAR ${barIndex + 1}',
                      style: const TextStyle(
                        color: MakasnaTheme.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: MakasnaTheme.textDim, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pilih channel audio stream SRT yang ingin dipantau pada bar ini:',
                  style: TextStyle(color: MakasnaTheme.textDim, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(8, (i) {
                    final chNum = i + 1;
                    final isCurrent = _assignedChannels[barIndex] == chNum;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _assignedChannels[barIndex] = chNum;
                        });
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 72,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isCurrent ? MakasnaTheme.cyanDim : MakasnaTheme.panelInput,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrent ? MakasnaTheme.cyan : MakasnaTheme.border,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'CH $chNum',
                              style: TextStyle(
                                color: isCurrent ? MakasnaTheme.cyan : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              chNum % 2 == 1 ? 'Left' : 'Right',
                              style: TextStyle(
                                color: isCurrent ? Colors.white70 : MakasnaTheme.textDim,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelBar(int barIndex, String label, double level, double peakHold) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          // Tappable channel selector chip
          InkWell(
            onTap: () => _showChannelPicker(context, barIndex),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: MakasnaTheme.border, width: 0.8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: MakasnaTheme.cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: MakasnaTheme.textDim, size: 12),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Active Level Bar Track
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // Background Track
                Container(
                  height: _channelCount == 4 ? 10 : 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B101B),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                ),

                // Dynamic Gradient Level Fill
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: level.clamp(0.0, 1.0),
                    child: Container(
                      height: _channelCount == 4 ? 10 : 12,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF10B981), // Green (Safe zone)
                            Color(0xFF22C55E),
                            Color(0xFFF59E0B), // Amber (Sweet spot 0 VU / -18 dBFS)
                            Color(0xFFEF4444), // Red (Clip warning)
                          ],
                          stops: [0.0, 0.65, 0.85, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // Peak Hold Tick Marker
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
                          height: _channelCount == 4 ? 12 : 14,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxLevel = _levels.take(_channelCount).fold(0.0, (a, b) => max(a, b));
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
          // Header Bar: Title, Scale Selector (dBFS / dBVU), Channels (2 CH / 4 CH), and Peak Readout
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
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),

              // Interactive Controls: Scale toggle & Channel count toggle & Readout
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scale Mode Toggle: dBFS vs dBVU
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: MakasnaTheme.border, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _scale = MeterScale.dbfs),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _scale == MeterScale.dbfs ? MakasnaTheme.cyanDim : Colors.transparent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'dBFS',
                              style: TextStyle(
                                color: _scale == MeterScale.dbfs ? MakasnaTheme.cyan : MakasnaTheme.textDim,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _scale = MeterScale.dbvu),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _scale == MeterScale.dbvu ? MakasnaTheme.cyanDim : Colors.transparent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'dBVU',
                              style: TextStyle(
                                color: _scale == MeterScale.dbvu ? MakasnaTheme.cyan : MakasnaTheme.textDim,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Channels Count Toggle: 2 CH vs 4 CH
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: MakasnaTheme.border, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _channelCount = 2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _channelCount == 2 ? MakasnaTheme.blueLight.withOpacity(0.25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '2-CH',
                              style: TextStyle(
                                color: _channelCount == 2 ? MakasnaTheme.blueLight : MakasnaTheme.textDim,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _channelCount = 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _channelCount == 4 ? MakasnaTheme.blueLight.withOpacity(0.25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '4-CH',
                              style: TextStyle(
                                color: _channelCount == 4 ? MakasnaTheme.blueLight : MakasnaTheme.textDim,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Real-time Peak Readout Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                      widget.isMuted ? 'MUTED' : _formatLevelReadout(),
                      style: TextStyle(
                        color: _isClipped
                            ? Colors.white
                            : (isAmberZone
                                ? MakasnaTheme.amber
                                : (widget.isMuted
                                    ? MakasnaTheme.textDim
                                    : MakasnaTheme.cyan)),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Render active channel bars (2 or 4 bars)
          for (int i = 0; i < _channelCount; i++)
            _buildChannelBar(
              i,
              'CH ${_assignedChannels[i]}',
              _levels[i],
              _peakHolds[i],
            ),

          const SizedBox(height: 4),

          // Scale Markings: Dynamic dBFS vs dBVU markings
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _scale == MeterScale.dbfs
                  ? const [
                      Text('-40', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                      Text('-24', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                      Text('-18', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                      Text('-12', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                      Text('-6', style: TextStyle(color: MakasnaTheme.amber, fontSize: 8, fontFamily: 'monospace')),
                      Text('0 dBFS', style: TextStyle(color: MakasnaTheme.red, fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    ]
                  : const [
                      Text('-20', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                      Text('-10', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                      Text('-7', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                      Text('-3', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 8, fontFamily: 'monospace')),
                      Text('0 VU', style: TextStyle(color: MakasnaTheme.cyan, fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                      Text('+3 VU', style: TextStyle(color: MakasnaTheme.red, fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}
