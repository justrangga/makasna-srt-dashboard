import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'providers/gateway_provider.dart';
import 'providers/recorder_provider.dart';
import 'screens/home_navigation_screen.dart';

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
      home: const HomeNavigationScreen(),
    );
  }
}
