class SystemStats {
  final double cpu;
  final double ramPercent;
  final int ramUsedMb;
  final int ramTotalMb;
  final double rxMbps;
  final double txMbps;
  final int activeRoutes;
  final int totalRoutes;

  SystemStats({
    this.cpu = 0.0,
    this.ramPercent = 0.0,
    this.ramUsedMb = 0,
    this.ramTotalMb = 0,
    this.rxMbps = 0.0,
    this.txMbps = 0.0,
    this.activeRoutes = 0,
    this.totalRoutes = 0,
  });

  factory SystemStats.fromJson(Map<String, dynamic> json) {
    return SystemStats(
      cpu: (json['cpu'] as num?)?.toDouble() ?? 0.0,
      ramPercent: (json['ram_percent'] as num?)?.toDouble() ?? 0.0,
      ramUsedMb: (json['ram_used_mb'] as num?)?.toInt() ?? 0,
      ramTotalMb: (json['ram_total_mb'] as num?)?.toInt() ?? 0,
      rxMbps: (json['rx_mbps'] as num?)?.toDouble() ?? 0.0,
      txMbps: (json['tx_mbps'] as num?)?.toDouble() ?? 0.0,
      activeRoutes: (json['active_routes'] as num?)?.toInt() ?? 0,
      totalRoutes: (json['total_routes'] as num?)?.toInt() ?? 0,
    );
  }
}
