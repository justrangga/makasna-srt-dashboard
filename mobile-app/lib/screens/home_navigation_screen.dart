import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/gateway_provider.dart';
import '../providers/recorder_provider.dart';
import 'signal_monitor_screen.dart';
import 'hyperdeck_recorder_screen.dart';
import 'routes_screen.dart';
import 'settings_profile_screen.dart';

class HomeNavigationScreen extends StatefulWidget {
  const HomeNavigationScreen({Key? key}) : super(key: key);

  @override
  State<HomeNavigationScreen> createState() => _HomeNavigationScreenState();
}

class _HomeNavigationScreenState extends State<HomeNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    SignalMonitorScreen(),
    HyperdeckRecorderScreen(),
    RoutesScreen(),
    SettingsProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayProvider>();
    final rec = context.watch<RecorderProvider>();

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.show_chart),
                if (gateway.srtData.totalPublishers > 0)
                  Positioned(
                    right: -6,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: MakasnaTheme.cyan,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${gateway.srtData.totalPublishers}',
                        style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Signal',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.fiber_manual_record,
                  color: rec.state.active ? MakasnaTheme.red : null,
                ),
                if (rec.state.active)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: MakasnaTheme.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: MakasnaTheme.red.withOpacity(0.8), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Recorder',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.alt_route),
                if (gateway.stats.activeRoutes > 0)
                  Positioned(
                    right: -6,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: MakasnaTheme.green,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${gateway.stats.activeRoutes}',
                        style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Routes',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.tune,
              color: gateway.isConnected ? null : MakasnaTheme.amber,
            ),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
