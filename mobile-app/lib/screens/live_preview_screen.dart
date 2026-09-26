import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/gateway_provider.dart';
import '../widgets/vu_meter_bar.dart';

class LivePreviewScreen extends StatelessWidget {
  final String streamId;

  const LivePreviewScreen({Key? key, required this.streamId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayProvider>();
    final hlsUrl = gateway.config.buildHlsUrl(streamId);
    final srtReadUrl = gateway.config.buildSrtReadUrl(streamId);

    return Scaffold(
      appBar: AppBar(
        title: Text('LIVE MONITOR: $streamId'),
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
            // Video Viewport Area (16:9 Broadcast Slate)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: MakasnaTheme.cyan.withOpacity(0.5), width: 1.5),
                ),
                child: Stack(
                  children: [
                    // Center Slate
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.live_tv, size: 44, color: MakasnaTheme.cyan),
                          const SizedBox(height: 10),
                          Text(
                            'LIVE SRT STREAM: $streamId',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'fMP4 Segmented Low Latency Egress',
                            style: TextStyle(color: MakasnaTheme.textDim, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    // Live Tally Top Left
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: MakasnaTheme.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '● LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Live Audio VU Meter
            const VuMeterBar(levelL: 0.72, levelR: 0.68, isClipped: false),
            const SizedBox(height: 16),

            // Connection URL Info Card
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
                  const Text('HLS Web Player URL:', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 11)),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
