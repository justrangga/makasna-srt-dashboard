class RouteModel {
  final String id;
  final String name;
  final String description;
  final bool running;
  final String? activeSource; // 'primary' or 'secondary'
  final Map<String, dynamic> primarySource;
  final Map<String, dynamic>? secondarySource;
  final List<dynamic> destinations;
  final bool failoverEnabled;
  final double rxMbps;
  final double txMbps;

  RouteModel({
    required this.id,
    required this.name,
    this.description = '',
    this.running = false,
    this.activeSource,
    this.primarySource = const {},
    this.secondarySource,
    this.destinations = const [],
    this.failoverEnabled = false,
    this.rxMbps = 0.0,
    this.txMbps = 0.0,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    return RouteModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Route',
      description: json['description']?.toString() ?? '',
      running: json['running'] == true,
      activeSource: json['active_source']?.toString(),
      primarySource: json['primary_source'] as Map<String, dynamic>? ?? {},
      secondarySource: json['secondary_source'] as Map<String, dynamic>?,
      destinations: json['destinations'] as List<dynamic>? ?? [],
      failoverEnabled: json['failover_enabled'] == true,
      rxMbps: (json['rx_mbps'] as num?)?.toDouble() ?? 0.0,
      txMbps: (json['tx_mbps'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
