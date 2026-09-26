class RecorderState {
  final bool active;
  final String? routeId;
  final String? feedName;
  final int elapsedSeconds;
  final String format; // 'mp4' or 'mov'
  final String? currentFile;
  final int segmentSeconds;

  RecorderState({
    this.active = false,
    this.routeId,
    this.feedName,
    this.elapsedSeconds = 0,
    this.format = 'mp4',
    this.currentFile,
    this.segmentSeconds = 900,
  });

  String get timecodeString {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    final frames = 0; // Simulated 00-24
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  factory RecorderState.fromJson(Map<String, dynamic> json) {
    return RecorderState(
      active: json['recording'] == true || json['active'] == true,
      routeId: json['route_id']?.toString(),
      feedName: json['feed_name']?.toString() ?? json['stream_id']?.toString(),
      elapsedSeconds: (json['elapsed_seconds'] as num?)?.toInt() ?? 0,
      format: json['format']?.toString() ?? 'mp4',
      currentFile: json['current_file']?.toString(),
      segmentSeconds: (json['segment_seconds'] as num?)?.toInt() ?? 900,
    );
  }
}
