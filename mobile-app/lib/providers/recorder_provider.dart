import 'dart:async';
import 'package:flutter/material.dart';
import '../models/recorder_state.dart';
import '../services/api_client.dart';

class RecorderProvider extends ChangeNotifier {
  ApiClient? _apiClient;

  RecorderState _state = RecorderState();
  RecorderState get state => _state;

  String? _selectedFeed;
  String? get selectedFeed => _selectedFeed;

  String _format = 'mp4'; // 'mp4' or 'mov'
  String get format => _format;

  String _bitrateMode = 'copy'; // 'copy', '10000', '6000', 'custom'
  String get bitrateMode => _bitrateMode;
  int _customBitrateKbps = 6000;
  int get customBitrateKbps => _customBitrateKbps;

  String _resolutionMode = 'original'; // 'original', '1080p', '720p'
  String get resolutionMode => _resolutionMode;

  int _segmentSeconds = 900; // 15 mins default
  int get segmentSeconds => _segmentSeconds;

  bool _isOperating = false;
  bool get isOperating => _isOperating;

  Timer? _statusTimer;

  void updateClient(ApiClient client) {
    _apiClient = client;
    _startStatusPolling();
  }

  void setFeed(String? feed) {
    _selectedFeed = feed;
    notifyListeners();
  }

  void setFormat(String fmt) {
    _format = fmt;
    notifyListeners();
  }

  void setBitrateMode(String mode, {int? customKbps}) {
    _bitrateMode = mode;
    if (customKbps != null) _customBitrateKbps = customKbps;
    notifyListeners();
  }

  void setResolutionMode(String res) {
    _resolutionMode = res;
    notifyListeners();
  }

  void setSegmentDuration(int seconds) {
    _segmentSeconds = seconds;
    notifyListeners();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => pollStatus());
  }

  Future<void> pollStatus() async {
    if (_apiClient == null) return;
    try {
      final target = _selectedFeed ?? 'active';
      final s = await _apiClient!.getRecordingStatus(target);
      _state = s;
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> startRecord() async {
    if (_apiClient == null || _selectedFeed == null) return false;
    _isOperating = true;
    notifyListeners();

    try {
      final opts = <String, dynamic>{
        'target_route': _selectedFeed,
        'record_format': _format,
        'segment_duration': _segmentSeconds,
        'record_bitrate': _bitrateMode == 'custom' ? _customBitrateKbps : _bitrateMode,
        'record_resolution': _resolutionMode,
      };

      final ok = await _apiClient!.startRecording(_selectedFeed!, opts);
      if (ok) {
        await pollStatus();
      }
      return ok;
    } finally {
      _isOperating = false;
      notifyListeners();
    }
  }

  Future<bool> stopRecord() async {
    if (_apiClient == null) return false;
    _isOperating = true;
    notifyListeners();

    try {
      final target = _state.routeId ?? _selectedFeed ?? 'active';
      final ok = await _apiClient!.stopRecording(target);
      if (ok) {
        await pollStatus();
      }
      return ok;
    } finally {
      _isOperating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }
}
