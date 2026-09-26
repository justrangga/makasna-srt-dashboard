import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/gateway_provider.dart';
import '../providers/recorder_provider.dart';
import '../widgets/tally_lamp.dart';
import '../widgets/timecode_display.dart';
import '../widgets/vu_meter_bar.dart';

class HyperdeckRecorderScreen extends StatefulWidget {
  const HyperdeckRecorderScreen({Key? key}) : super(key: key);

  @override
  State<HyperdeckRecorderScreen> createState() => _HyperdeckRecorderScreenState();
}

class _HyperdeckRecorderScreenState extends State<HyperdeckRecorderScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gateway = context.read<GatewayProvider>();
      context.read<RecorderProvider>().updateClient(gateway.apiClient);
    });
  }

  void _confirmStartRecord() {
    final rec = context.read<RecorderProvider>();
    if (rec.selectedFeed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: MakasnaTheme.amber,
          content: Text('Silakan pilih FEED SOURCE terlebih dahulu.'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MakasnaTheme.panelElevated,
        title: Row(
          children: const [
            Icon(Icons.fiber_manual_record, color: MakasnaTheme.red, size: 20),
            SizedBox(width: 8),
            Text('MULAI PEREKAMAN MASTER', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: Text(
          'Rekam feed [${rec.selectedFeed}] dengan format ${rec.format.toUpperCase()}?\n\n'
          'Perekaman berjalan independen tanpa memutus siaran utama.',
          style: const TextStyle(color: MakasnaTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            child: const Text('Batal', style: TextStyle(color: MakasnaTheme.textDim)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: MakasnaTheme.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('● MULAI REKAM'),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await rec.startRecord();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: ok ? MakasnaTheme.red : MakasnaTheme.amber,
                    content: Text(ok ? 'Perekaman dimulai!' : 'Gagal memulai perekaman'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmStopRecord() {
    final rec = context.read<RecorderProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MakasnaTheme.panelElevated,
        title: const Text('HENTIKAN PEREKAMAN?'),
        content: const Text(
          'Sinyal SIGINT akan dikirim ke FFmpeg untuk menutup header atom MP4/MOV secara bersih.',
          style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            child: const Text('Batal', style: TextStyle(color: MakasnaTheme.textDim)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              foregroundColor: Colors.white,
            ),
            child: const Text('■ HENTIKAN REKAMAN'),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await rec.stopRecord();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: ok ? MakasnaTheme.green : MakasnaTheme.amber,
                    content: Text(ok ? 'Perekaman dihentikan bersih!' : 'Gagal menghentikan rekaman'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayProvider>();
    final rec = context.watch<RecorderProvider>();

    // Build feed options: inbound feeds + routes
    final feedOptions = <DropdownMenuItem<String>>[];
    for (final pub in gateway.srtData.publishers) {
      feedOptions.add(
        DropdownMenuItem(
          value: 'inbound:${pub.streamId}',
          child: Text('Live Ingest: ${pub.streamId} (${pub.mbpsRx} Mbps)'),
        ),
      );
    }
    for (final r in gateway.routes) {
      feedOptions.add(
        DropdownMenuItem(
          value: r.id,
          child: Text('Route: ${r.name}'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HYPERDECK MASTER RECORDER'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TallyLamp(isRecording: rec.state.active),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timecode OSD Display
            TimecodeDisplay(
              timecode: rec.state.timecodeString,
              isRecording: rec.state.active,
              format: rec.format,
              feedName: rec.state.feedName ?? rec.selectedFeed,
            ),
            const SizedBox(height: 14),

            // Real-time True Peak VU Meter
            const VuMeterBar(levelL: 0.68, levelR: 0.64, isClipped: false),
            const SizedBox(height: 16),

            // Controls Panel Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MakasnaTheme.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MakasnaTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'RECORDING CONFIGURATION',
                    style: TextStyle(
                      color: MakasnaTheme.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Feed Source Dropdown
                  DropdownButtonFormField<String>(
                    value: rec.selectedFeed,
                    dropdownColor: MakasnaTheme.panelElevated,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'PILIH SUMBER FEED KAMERA',
                      prefixIcon: Icon(Icons.input, color: MakasnaTheme.cyan, size: 18),
                    ),
                    items: feedOptions.isEmpty
                        ? [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Belum ada feed aktif di server'),
                            )
                          ]
                        : feedOptions,
                    onChanged: rec.state.active ? null : (val) => rec.setFeed(val),
                  ),
                  const SizedBox(height: 12),

                  // Format Selector (MP4 vs MOV)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: rec.format == 'mp4' ? MakasnaTheme.cyanDim : null,
                            side: BorderSide(
                              color: rec.format == 'mp4' ? MakasnaTheme.cyan : MakasnaTheme.border,
                            ),
                          ),
                          onPressed: rec.state.active ? null : () => rec.setFormat('mp4'),
                          child: const Text('MP4 Universal'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: rec.format == 'mov' ? MakasnaTheme.cyanDim : null,
                            side: BorderSide(
                              color: rec.format == 'mov' ? MakasnaTheme.cyan : MakasnaTheme.border,
                            ),
                          ),
                          onPressed: rec.state.active ? null : () => rec.setFormat('mov'),
                          child: const Text('QuickTime MOV'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Segment Duration
                  DropdownButtonFormField<int>(
                    value: rec.segmentSeconds,
                    dropdownColor: MakasnaTheme.panelElevated,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'DURASI SEGMEN FILE',
                      prefixIcon: Icon(Icons.timer_outlined, color: MakasnaTheme.amber, size: 18),
                    ),
                    items: const [
                      DropdownMenuItem(value: 900, child: Text('15 Menit per Segmen')),
                      DropdownMenuItem(value: 1800, child: Text('30 Menit per Segmen')),
                      DropdownMenuItem(value: 3600, child: Text('1 Jam per Segmen')),
                      DropdownMenuItem(value: 0, child: Text('Single File (Non-Segmented)')),
                    ],
                    onChanged: rec.state.active ? null : (val) => rec.setSegmentDuration(val ?? 900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Big Tactile Buttons (RECORD & STOP)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rec.state.active ? const Color(0xFF3F1D1D) : MakasnaTheme.red,
                        foregroundColor: Colors.white,
                        elevation: rec.state.active ? 0 : 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: rec.state.active ? null : _confirmStartRecord,
                      icon: const Icon(Icons.fiber_manual_record, size: 20),
                      label: const Text(
                        'RECORD',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rec.state.active ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                        foregroundColor: rec.state.active ? Colors.white : MakasnaTheme.textDim,
                        side: BorderSide(
                          color: rec.state.active ? MakasnaTheme.cyan : MakasnaTheme.border,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: rec.state.active ? _confirmStopRecord : null,
                      icon: const Icon(Icons.stop, size: 22),
                      label: const Text(
                        'STOP',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
