import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'providers/gateway_provider.dart';
import 'providers/recorder_provider.dart';
import 'screens/home_navigation_screen.dart';
import 'screens/welcome_server_screen.dart';
import 'services/preferences_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force dark system navigation bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: MakasnaTheme.panel,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GatewayProvider()),
        ChangeNotifierProvider(create: (_) => RecorderProvider()),
      ],
      child: const MakasnaRemoteApp(),
    ),
  );
}

class MakasnaRemoteApp extends StatelessWidget {
  const MakasnaRemoteApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MAKASNA GATEWAY REMOTE',
      debugShowCheckedModeBanner: false,
      theme: MakasnaTheme.themeData,
      home: const AppLauncher(),
    );
  }
}

/// Fast Splash Resolver: Automatically restores cached server session and connects
class AppLauncher extends StatefulWidget {
  const AppLauncher({Key? key}) : super(key: key);

  @override
  State<AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends State<AppLauncher> {
  final PreferencesService _prefs = PreferencesService();

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    // Brief settle delay to allow Provider initialization
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    final hasSession = await _prefs.hasCachedValidSession();
    if (hasSession) {
      final config = await _prefs.loadServerConfig();
      if (mounted && config.hasValidHost) {
        final gateway = context.read<GatewayProvider>();
        await gateway.updateConfig(config);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeNavigationScreen()),
          );
          return;
        }
      }
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeServerScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MakasnaTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: MakasnaTheme.cyan.withOpacity(0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/images/logo.png', width: 72, height: 72),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'MAKASNA REMOTE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Memeriksa sesi login tersimpan...',
              style: TextStyle(
                color: MakasnaTheme.cyan,
                fontSize: 11.5,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MakasnaTheme.cyan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
