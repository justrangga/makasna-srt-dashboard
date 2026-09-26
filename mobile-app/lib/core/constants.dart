class AppConstants {
  static const String appName = 'MAKASNA GATEWAY';
  static const String appTagline = 'Mobile Broadcast Controller';
  static const String appVersion = '1.2.0';

  // Default server coordinates: empty so client inputs their own server
  static const String defaultServerIp = '';
  static const int defaultHttpPort = 8080;
  static const int defaultSrtPort = 8890;
  static const int defaultRtspPort = 8554;
  static const int defaultHlsPort = 8888;
  static const String defaultUser = 'admin';
  static const String defaultPass = '';

  static const int pollingIntervalSeconds = 2;
  static const int connectionTimeoutSeconds = 5;
}
