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

  String get cleanHost {
    var h = host.trim();
    h = h.replaceAll(RegExp(r'^https?://', caseSensitive: false), '');
    h = h.split('/')[0];
    if (h.contains(':')) {
      h = h.split(':')[0];
    }
    return h;
  }

  String get baseUrl {
    final clean = cleanHost;
    if (useHttps || clean == 'stream.makasna.com') {
      if (httpPort == 443 || httpPort == 80 || httpPort == 8080) {
        return 'https://$clean';
      }
      return 'https://$clean:$httpPort';
    }
    return 'http://$clean:$httpPort';
  }

  String get srtListenBaseUrl {
    return 'srt://$cleanHost:$srtPort';
  }

  bool get hasValidHost => cleanHost.isNotEmpty;

  String buildSrtReadUrl(String streamId, {int latencyMs = 2000}) {
    final clean = cleanStreamPath(streamId);
    return 'srt://$cleanHost:$srtPort?streamid=read:$clean&latency=${latencyMs * 1000}';
  }

  String buildSrtPublishUrl(String streamId, {int latencyMs = 2000}) {
    final clean = cleanStreamPath(streamId);
    return 'srt://$cleanHost:$srtPort?streamid=publish:$clean&latency=${latencyMs * 1000}';
  }

  static String cleanStreamPath(String rawStreamId) {
    var s = rawStreamId.trim();
    if (s.startsWith('publish:')) s = s.substring(8);
    else if (s.startsWith('read:')) s = s.substring(5);
    else if (s.startsWith('inbound:')) s = s.substring(8);
    return s;
  }

  String buildHlsUrl(String streamId) {
    final clean = cleanStreamPath(streamId);
    return '$baseUrl/hls/$clean/index.m3u8';
  }

  String buildDirectHlsUrl(String streamId) {
    final clean = cleanStreamPath(streamId);
    return 'http://$cleanHost:8888/$clean/index.m3u8';
  }

  List<String> getHlsCandidates(String streamId) {
    final clean = cleanStreamPath(streamId);
    final candidates = <String>[];

    // 1. Native MediaMTX direct port 8888 (Fastest, zero proxy delay)
    if (!useHttps && cleanHost != 'stream.makasna.com') {
      candidates.add('http://$cleanHost:8888/$clean/index.m3u8');
      candidates.add('http://$cleanHost:8888/$clean/video1_stream.m3u8');
    }

    // 2. Gateway Proxy (Port 8080 or Cloudflare HTTPS 443)
    candidates.add('$baseUrl/hls/$clean/index.m3u8');
    candidates.add('$baseUrl/hls/$clean/video1_stream.m3u8');

    return candidates;
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
