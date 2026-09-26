import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/route_model.dart';
import '../providers/gateway_provider.dart';

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({Key? key}) : super(key: key);

  Widget _buildRouteCard(BuildContext context, RouteModel route) {
    final gateway = context.read<GatewayProvider>();

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
                Row(
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
                    Text(
                      route.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                    ),
                  ],
                ),
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
              ],
            ),
            if (route.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                route.description,
                style: const TextStyle(color: MakasnaTheme.textSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            const Divider(color: MakasnaTheme.border, height: 1),
            const SizedBox(height: 10),

            // Active Source Info
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
                Text(
                  '${route.destinations.length} Fan-outs',
                  style: const TextStyle(
                    color: MakasnaTheme.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Actions: Start / Stop & Failover Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
                    label: Text('Switch to ${route.activeSource == 'primary' ? 'Backup' : 'Primary'}', style: const TextStyle(fontSize: 11)),
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
                  label: Text(route.running ? 'Stop' : 'Start', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
        title: const Text('ROUTES WORKSPACE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => gateway.refreshAll(),
          ),
        ],
      ),
      body: gateway.routes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.alt_route, size: 40, color: MakasnaTheme.textDim),
                  SizedBox(height: 10),
                  Text(
                    'Belum ada rute streaming terkonfigurasi di server',
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
                itemCount: gateway.routes.length,
                itemBuilder: (context, i) => _buildRouteCard(context, gateway.routes[i]),
              ),
            ),
    );
  }
}
