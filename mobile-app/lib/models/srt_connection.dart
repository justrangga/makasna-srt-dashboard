class SrtConnection {
  final String id;
  final String streamId;
  final String remoteAddr;
  final String state; // 'publish' or 'read'
  final double mbpsRate;
  final double mbpsRx;
  final double mbpsTx;
  final double rttMs;
  final double lossPct;
  final int droppedPackets;
  final double bytesMb;
  final double linkCapacityMbps;
  final int durationSeconds;
  final String health; // 'Healthy', 'Degraded', 'Critical'
  final List<String> tracks;
  final bool routed;
  final String? routeId;
  final String? routeName;

  SrtConnection({
    required this.id,
    required this.streamId,
    required this.remoteAddr,
    required this.state,
    this.mbpsRate = 0.0,
    this.mbpsRx = 0.0,
    this.mbpsTx = 0.0,
    this.rttMs = 0.0,
    this.lossPct = 0.0,
    this.droppedPackets = 0,
    this.bytesMb = 0.0,
    this.linkCapacityMbps = 0.0,
    this.durationSeconds = 0,
    this.health = 'Healthy',
    this.tracks = const [],
    this.routed = false,
    this.routeId,
    this.routeName,
  });

  bool get isPublisher => state == 'publish';
  bool get isReader => state == 'read';

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    final h = m ~/ 60;
    final remM = m % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${remM.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  factory SrtConnection.fromJson(Map<String, dynamic> json) {
    return SrtConnection(
      id: json['id']?.toString() ?? '',
      streamId: json['stream_id']?.toString() ?? '',
      remoteAddr: json['remote_addr']?.toString() ?? '',
      state: json['state']?.toString() ?? 'publish',
      mbpsRate: (json['mbps_rate'] as num?)?.toDouble() ?? 0.0,
      mbpsRx: (json['mbps_rx'] as num?)?.toDouble() ?? 0.0,
      mbpsTx: (json['mbps_tx'] as num?)?.toDouble() ?? 0.0,
      rttMs: (json['rtt_ms'] as num?)?.toDouble() ?? 0.0,
      lossPct: (json['loss_pct'] as num?)?.toDouble() ?? 0.0,
      droppedPackets: (json['dropped_packets'] as num?)?.toInt() ?? 0,
      bytesMb: (json['bytes_mb'] as num?)?.toDouble() ?? (json['bytes_received_mb'] as num?)?.toDouble() ?? 0.0,
      linkCapacityMbps: (json['link_capacity_mbps'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      health: json['health']?.toString() ?? 'Healthy',
      tracks: (json['tracks'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      routed: json['routed'] == true,
      routeId: json['route_id']?.toString(),
      routeName: json['route_name']?.toString(),
    );
  }
}

class SrtInboundPayload {
  final List<SrtConnection> publishers;
  final List<SrtConnection> readers;
  final int totalPublishers;
  final int totalReaders;
  final double totalRxMbps;
  final double totalTxMbps;
  final int srtPort;
  final String serverHost;

  SrtInboundPayload({
    this.publishers = const [],
    this.readers = const [],
    this.totalPublishers = 0,
    this.totalReaders = 0,
    this.totalRxMbps = 0.0,
    this.totalTxMbps = 0.0,
    this.srtPort = 8890,
    this.serverHost = '',
  });

  factory SrtInboundPayload.fromJson(Map<String, dynamic> json) {
    final pubs = (json['publishers'] as List<dynamic>?)
            ?.map((e) => SrtConnection.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final rdrs = (json['readers'] as List<dynamic>?)
            ?.map((e) => SrtConnection.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return SrtInboundPayload(
      publishers: pubs,
      readers: rdrs,
      totalPublishers: (json['total_publishers'] as num?)?.toInt() ?? pubs.length,
      totalReaders: (json['total_readers'] as num?)?.toInt() ?? rdrs.length,
      totalRxMbps: (json['total_rx_rate_mbps'] as num?)?.toDouble() ?? 0.0,
      totalTxMbps: (json['total_tx_rate_mbps'] as num?)?.toDouble() ?? 0.0,
      srtPort: (json['srt_port'] as num?)?.toInt() ?? 8890,
      serverHost: json['server_host']?.toString() ?? '',
    );
  }
}
