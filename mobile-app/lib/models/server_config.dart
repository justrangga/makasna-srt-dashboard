import '../core/constants.dart';

class ServerConfig {
  String host;
  int httpPort;
  int srtPort;
  String username;
  String password;
  bool useHttps;
  int pollIntervalSec;

  ServerConfig({
    this.host = AppConstants.defaultServerIp,
    this.httpPort = AppConstants.defaultHttpPort,
    this.srtPort = AppConstants.defaultSrtPort,
    this.username = AppConstants.defaultUser,
    this.password = AppConstants.defaultPass,
    this.useHttps = false,
    this.pollIntervalSec = AppConstants.pollingIntervalSeconds,
  });

  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$httpPort';
  }

  String get srtListenBaseUrl {
    return 'srt://$host:$srtPort';
  }

  String buildSrtReadUrl(String streamId, {int latencyMs = 200}) {
    return 'srt://$host:$srtPort?streamid=read:$streamId&latency=${latencyMs * 1000}';
  }

  String buildSrtPublishUrl(String streamId, {int latencyMs = 200}) {
    return 'srt://$host:$srtPort?streamid=publish:$streamId&latency=${latencyMs * 1000}';
  }

  String buildHlsUrl(String streamId) {
    return '$baseUrl/hls/$streamId/index.m3u8';
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'httpPort': httpPort,
    'srtPort': srtPort,
    'username': username,
    'password': password,
    'useHttps': useHttps,
    'pollIntervalSec': pollIntervalSec,
  };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
    host: json['host'] ?? AppConstants.defaultServerIp,
    httpPort: json['httpPort'] ?? AppConstants.defaultHttpPort,
    srtPort: json['srtPort'] ?? AppConstants.defaultSrtPort,
    username: json['username'] ?? AppConstants.defaultUser,
    password: json['password'] ?? AppConstants.defaultPass,
    useHttps: json['useHttps'] ?? false,
    pollIntervalSec: json['pollIntervalSec'] ?? AppConstants.pollingIntervalSeconds,
  );

  ServerConfig copyWith({
    String? host,
    int? httpPort,
    int? srtPort,
    String? username,
    String? password,
    bool? useHttps,
    int? pollIntervalSec,
  }) {
    return ServerConfig(
      host: host ?? this.host,
      httpPort: httpPort ?? this.httpPort,
      srtPort: srtPort ?? this.srtPort,
      username: username ?? this.username,
      password: password ?? this.password,
      useHttps: useHttps ?? this.useHttps,
      pollIntervalSec: pollIntervalSec ?? this.pollIntervalSec,
    );
  }
}
