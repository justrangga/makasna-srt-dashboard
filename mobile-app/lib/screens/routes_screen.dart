import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/route_model.dart';
import '../providers/gateway_provider.dart';
import 'live_preview_screen.dart';
import 'route_editor_screen.dart';

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({Key? key}) : super(key: key);

  void _confirmDeleteRoute(BuildContext context, RouteModel route) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MakasnaTheme.panelElevated,
        title: const Text('HAPUS RUTE SIARAN?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Apakah Anda yakin ingin menghapus rute "${route.name}"?\n\n'
          'Tindakan ini akan menghentikan seluruh pipeline fan-out yang terhubung pada rute ini.',
          style: const TextStyle(color: MakasnaTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            child: const Text('Batal', style: TextStyle(color: MakasnaTheme.textDim)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MakasnaTheme.red, foregroundColor: Colors.white),
            child: const Text('Hapus Rute'),
            onPressed: () async {
              Navigator.pop(ctx);
              final gateway = context.read<GatewayProvider>();
              final ok = await gateway.deleteRoute(route.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: ok ? MakasnaTheme.green : MakasnaTheme.red,
                    content: Text(ok ? 'Rute "${route.name}" berhasil dihapus!' : 'Gagal menghapus rute'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(BuildContext context, RouteModel route) {
    final gateway = context.read<GatewayProvider>();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Name, Status & 3-dots Menu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: route.running ? MakasnaTheme.green : const Color(0xFF52525B),
                          shape: BoxShape.circle,
                          boxShadow: route.running
                              ? [BoxShadow(color: MakasnaTheme.green.withOpacity(0.6), blurRadius: 6)]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          route.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: route.running ? const Color(0x2610B981) : const Color(0x2652525B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: route.running ? MakasnaTheme.green.withOpacity(0.4) : MakasnaTheme.border,
                        ),
                      ),
                      child: Text(
                        route.running ? 'RUNNING' : 'STOPPED',
                        style: TextStyle(
                          color: route.running ? MakasnaTheme.green : MakasnaTheme.textDim,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: MakasnaTheme.textDim, size: 20),
                      color: MakasnaTheme.panelElevated,
                      onSelected: (val) {
                        if (val == 'edit') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => RouteEditorScreen(route: route)),
                          );
                        } else if (val == 'delete') {
                          _confirmDeleteRoute(context, route);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 16, color: MakasnaTheme.cyan),
                              SizedBox(width: 8),
                              Text('Edit Konfigurasi Rute', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 16, color: MakasnaTheme.red),
                              SizedBox(width: 8),
                              Text('Hapus Rute', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (route.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                route.description,
                style: const TextStyle(color: MakasnaTheme.textSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(color: MakasnaTheme.border, height: 1),
            const SizedBox(height: 8),

            // Active Source Info & Fan-out Count
            Row(
              children: [
                const Icon(Icons.videocam_outlined, size: 14, color: MakasnaTheme.cyan),
                const SizedBox(width: 6),
                const Text('Source: ', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 11)),
                Text(
                  route.activeSource?.toUpperCase() ?? 'PRIMARY',
                  style: const TextStyle(
                    color: MakasnaTheme.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: MakasnaTheme.amberDim,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${route.destinations.length} Fan-outs',
                    style: const TextStyle(
                      color: MakasnaTheme.amber,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            // Destinations mini badges
            if (route.destinations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: route.destinations.map((d) {
                  final label = (d is Map ? d['label'] : 'Dest') ?? 'Dest';
                  final type = (d is Map ? d['type'] : 'srt') ?? 'srt';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF334155), width: 0.5),
                    ),
                    child: Text(
                      '${type.toString().toUpperCase()}: $label',
                      style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontFamily: 'monospace'),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),

            // Actions: Preview, Failover Switch, Start/Stop
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (route.running) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MakasnaTheme.cyan,
                      side: const BorderSide(color: MakasnaTheme.cyan),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LivePreviewScreen(streamId: 'route_${route.id}'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_circle_outline, size: 14),
                    label: const Text('Preview', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                ],
                if (route.failoverEnabled && route.secondarySource != null) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MakasnaTheme.amber,
                      side: const BorderSide(color: MakasnaTheme.amber),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      final next = route.activeSource == 'primary' ? 'secondary' : 'primary';
                      await gateway.switchRouteSource(route.id, next);
                    },
                    icon: const Icon(Icons.swap_horiz, size: 14),
                    label: Text(
                      'Switch ${route.activeSource == 'primary' ? 'Backup' : 'Primary'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: route.running ? const Color(0xFF3F1D1D) : MakasnaTheme.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    if (route.running) {
                      await gateway.stopRoute(route.id);
                    } else {
                      await gateway.startRoute(route.id);
                    }
                  },
                  icon: Icon(route.running ? Icons.stop : Icons.play_arrow, size: 14),
                  label: Text(
                    route.running ? 'Stop' : 'Start',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('assets/images/logo.png', width: 24, height: 24),
            ),
            const SizedBox(width: 8),
            const Text('ROUTES WORKSPACE'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: MakasnaTheme.cyan),
            tooltip: 'Tambah Rute Baru',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RouteEditorScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => gateway.refreshAll(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MakasnaTheme.cyan,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('BUAT RUTE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RouteEditorScreen()),
          );
        },
      ),
      body: gateway.routes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.alt_route, size: 48, color: MakasnaTheme.textDim),
                    const SizedBox(height: 12),
                    const Text(
                      'Belum ada rute streaming di server',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Rute menghubungkan sumber video (Inbound SRT atau port listen) ke fan-out tujuan penyiaran.',
                      style: TextStyle(color: MakasnaTheme.textDim, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MakasnaTheme.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RouteEditorScreen()),
                        );
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('TAMBAH RUTE PERTAMA', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              color: MakasnaTheme.cyan,
              onRefresh: () => gateway.refreshAll(),
              child: ListView.builder(
                padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 80),
                itemCount: gateway.routes.length,
                itemBuilder: (context, i) => _buildRouteCard(context, gateway.routes[i]),
              ),
            ),
    );
  }
}
