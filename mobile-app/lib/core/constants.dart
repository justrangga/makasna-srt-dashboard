class AppConstants {
  static const String appName = 'MAKASNA GATEWAY';
  static const String appTagline = 'Mobile Broadcast Controller';
  static const String appVersion = '1.0.0';

  // Default server coordinates (Debian 12 Gateway Production Server)
  static const String defaultServerIp = '139.190.97.109';
  static const int defaultHttpPort = 8080;
  static const int defaultSrtPort = 8890;
  static const int defaultRtspPort = 8554;
  static const int defaultHlsPort = 8888;
  static const String defaultUser = 'admin';
  static const String defaultPass = '@linux1234';

  static const int pollingIntervalSeconds = 2;
  static const int connectionTimeoutSeconds = 5;
}
