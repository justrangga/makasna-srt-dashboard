import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/srt_connection.dart';
import '../providers/gateway_provider.dart';
import '../widgets/metric_card.dart';
import 'live_preview_screen.dart';
import 'welcome_server_screen.dart';

class SignalMonitorScreen extends StatefulWidget {
  const SignalMonitorScreen({Key? key}) : super(key: key);

  @override
  State<SignalMonitorScreen> createState() => _SignalMonitorScreenState();
}

class _SignalMonitorScreenState extends State<SignalMonitorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: MakasnaTheme.panelElevated,
        content: Text('$label berhasil disalin ke clipboard!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildStatusDot(String health) {
    Color c = MakasnaTheme.green;
    if (health == 'Degraded') c = MakasnaTheme.amber;
    if (health == 'Critical') c = MakasnaTheme.red;

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withOpacity(0.6), blurRadius: 4)],
      ),
    );
  }

  Widget _buildConnectionCard(SrtConnection conn, bool isPublisher) {
    final gateway = context.read<GatewayProvider>();
    final srtUrl = isPublisher
        ? gateway.config.buildSrtPublishUrl(conn.streamId)
        : gateway.config.buildSrtReadUrl(conn.streamId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPublisher ? MakasnaTheme.cyanDim : const Color(0x263B82F6),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isPublisher ? MakasnaTheme.cyan.withOpacity(0.4) : const Color(0x403B82F6),
                    ),
                  ),
                  child: Text(
                    '${isPublisher ? 'publish' : 'read'}:${conn.streamId}',
                    style: TextStyle(
                      color: isPublisher ? MakasnaTheme.cyan : MakasnaTheme.blueLight,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Row(
                  children: [
                    _buildStatusDot(conn.health),
                    const SizedBox(width: 6),
                    Text(
                      conn.health.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: conn.health == 'Healthy'
                            ? MakasnaTheme.green
                            : conn.health == 'Degraded'
                                ? MakasnaTheme.amber
                                : MakasnaTheme.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.language, size: 14, color: MakasnaTheme.textDim),
                const SizedBox(width: 6),
                Text(
                  conn.remoteAddr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  conn.formattedDuration,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: MakasnaTheme.textDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: MakasnaTheme.border, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('THROUGHPUT', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 9.5)),
                    const SizedBox(height: 2),
                    Text(
                      isPublisher ? '↓ ${conn.mbpsRx} Mbps' : '↑ ${conn.mbpsTx} Mbps',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LOSS %', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 9.5)),
                    const SizedBox(height: 2),
                    Text(
                      '${conn.lossPct}% (${conn.droppedPackets} drops)',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: conn.lossPct > 1 ? MakasnaTheme.red : MakasnaTheme.green,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RTT LATENCY', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 9.5)),
                    const SizedBox(height: 2),
                    Text(
                      '${conn.rttMs} ms',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MakasnaTheme.cyan,
                    side: const BorderSide(color: MakasnaTheme.cyan),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _copyToClipboard(srtUrl, 'URL SRT'),
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy URL', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MakasnaTheme.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LivePreviewScreen(streamId: conn.streamId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_arrow, size: 14),
                  label: const Text('Preview', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayProvider>();
    final srt = gateway.srtData;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('assets/images/logo.png', width: 24, height: 24),
            ),
            const SizedBox(width: 8),
            const Text('SIGNAL MONITOR'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_outlined, color: MakasnaTheme.cyan),
            tooltip: 'Ganti Server / Panduan',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WelcomeServerScreen(isSwitching: true)),
              );
            },
          ),
          IconButton(
            icon: gateway.isConnecting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: MakasnaTheme.cyan),
                  )
                : const Icon(Icons.refresh),
            onPressed: () => gateway.refreshAll(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Telemetry overview cards
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Ingest In',
                    value: '↓ ${srt.totalRxMbps.toStringAsFixed(2)}',
                    subtext: '${srt.totalPublishers} camera feeds',
                    icon: Icons.download,
                    accentColor: MakasnaTheme.cyan,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: 'Listeners Out',
                    value: '↑ ${srt.totalTxMbps.toStringAsFixed(2)}',
                    subtext: '${srt.totalReaders} clients connected',
                    icon: Icons.upload,
                    accentColor: MakasnaTheme.blueLight,
                  ),
                ),
              ],
            ),
          ),

          // Subtabs
          Container(
            color: MakasnaTheme.panel,
            child: TabBar(
              controller: _tabController,
              indicatorColor: MakasnaTheme.cyan,
              labelColor: MakasnaTheme.cyan,
              unselectedLabelColor: MakasnaTheme.textDim,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('INGEST PUBLISHERS'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: MakasnaTheme.cyanDim,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${srt.totalPublishers}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('ACTIVE LISTENERS'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0x333B82F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${srt.totalReaders}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: MakasnaTheme.blueLight),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Subtab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Ingest Publishers View
                srt.publishers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.videocam_off_outlined, size: 40, color: MakasnaTheme.textDim),
                            SizedBox(height: 10),
                            Text(
                              'Belum ada encoder pengirim terhubung ke port 8890',
                              style: TextStyle(color: MakasnaTheme.textDim, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: MakasnaTheme.cyan,
                        onRefresh: () => gateway.refreshAll(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: srt.publishers.length,
                          itemBuilder: (context, i) => _buildConnectionCard(srt.publishers[i], true),
                        ),
                      ),

                // Active Listeners View
                srt.readers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.headphones_outlined, size: 40, color: MakasnaTheme.textDim),
                            SizedBox(height: 10),
                            Text(
                              'Belum ada client listener / PC Blackgate terhubung',
                              style: TextStyle(color: MakasnaTheme.textDim, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: MakasnaTheme.cyan,
                        onRefresh: () => gateway.refreshAll(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: srt.readers.length,
                          itemBuilder: (context, i) => _buildConnectionCard(srt.readers[i], false),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
