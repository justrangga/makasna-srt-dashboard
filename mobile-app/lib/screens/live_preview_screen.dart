import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/gateway_provider.dart';
import '../widgets/broadcast_video_player.dart';
import '../widgets/vu_meter_bar.dart';

class LivePreviewScreen extends StatefulWidget {
  final String streamId;

  const LivePreviewScreen({Key? key, required this.streamId}) : super(key: key);

  @override
  State<LivePreviewScreen> createState() => _LivePreviewScreenState();
}

class _LivePreviewScreenState extends State<LivePreviewScreen> {
  bool _isPlaying = true;
  bool _isMuted = true;

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayProvider>();
    final hlsUrl = gateway.config.buildHlsUrl(widget.streamId);
    final directHlsUrl = gateway.config.buildDirectHlsUrl(widget.streamId);
    final srtReadUrl = gateway.config.buildSrtReadUrl(widget.streamId);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('assets/images/logo.png', width: 24, height: 24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'LIVE MONITOR: ${widget.streamId}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy SRT Read URL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: srtReadUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SRT Read URL berhasil disalin!')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Smooth Broadcast Video Player (Hardware Accelerated ExoPlayer)
            BroadcastVideoPlayer(
              streamId: widget.streamId,
              aspectRatio: 16 / 9,
              autoPlay: true,
              showControls: true,
              defaultMuted: true,
              onPlayStateChanged: (playing) {
                if (mounted) setState(() => _isPlaying = playing);
              },
              onMuteStateChanged: (muted) {
                if (mounted) setState(() => _isMuted = muted);
              },
            ),
            const SizedBox(height: 14),

            // Live Audio VU Meter (Dynamic Peak Ballistics & Cadence)
            VuMeterBar(
              active: _isPlaying,
              isMuted: _isMuted,
            ),
            const SizedBox(height: 16),

            // Video Engine Technical Info Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C1019),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MakasnaTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: MakasnaTheme.cyan, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HARDWARE-ACCELERATED LOW LATENCY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Playback menggunakan MediaMTX fMP4 stream dengan buffer adaptive auto-recovery untuk mencegah stuttering.',
                          style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Downstream Connection URL Info Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MakasnaTheme.panelElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MakasnaTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DOWNSTREAM CONNECTION ENDPOINTS',
                    style: TextStyle(
                      color: MakasnaTheme.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('SRT Caller Pull URL (vMix / PC Blackgate):', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      srtReadUrl,
                      style: const TextStyle(color: MakasnaTheme.blueLight, fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('HLS Stream URL (Reverse Proxy):', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      hlsUrl,
                      style: const TextStyle(color: MakasnaTheme.cyan, fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Direct HLS Stream URL (Port 8888):', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      directHlsUrl,
                      style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
