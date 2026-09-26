import 'dart:async';
import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../models/system_stats.dart';
import '../models/srt_connection.dart';
import '../models/route_model.dart';
import '../services/api_client.dart';
import '../services/preferences_service.dart';

class GatewayProvider extends ChangeNotifier {
  final PreferencesService _prefsService = PreferencesService();
  late ApiClient _apiClient;

  ServerConfig _config = ServerConfig();
  ServerConfig get config => _config;

  SystemStats _stats = SystemStats();
  SystemStats get stats => _stats;

  SrtInboundPayload _srtData = SrtInboundPayload();
  SrtInboundPayload get srtData => _srtData;

  List<RouteModel> _routes = [];
  List<RouteModel> get routes => _routes;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  Timer? _pollTimer;

  GatewayProvider() {
    _apiClient = ApiClient(config: _config);
    _init();
  }

  Future<void> _init() async {
    _isConnecting = true;
    notifyListeners();

    _config = await _prefsService.loadServerConfig();
    _apiClient.updateConfig(_config);

    await refreshAll();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = Duration(seconds: _config.pollIntervalSec);
    _pollTimer = Timer.periodic(interval, (_) => refreshAll(silent: true));
  }

  Future<void> updateConfig(ServerConfig newConfig) async {
    _config = newConfig;
    await _prefsService.saveServerConfig(newConfig);
    _apiClient.updateConfig(_config);
    _startPolling();
    await refreshAll();
  }

  Future<void> refreshAll({bool silent = false}) async {
    if (_config.host.trim().isEmpty) {
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();
      return;
    }

    if (!silent) {
      _isConnecting = true;
      notifyListeners();
    }

    try {
      final results = await Future.wait([
        _apiClient.getSystemStats(),
        _apiClient.getSrtInbound(),
        _apiClient.getRoutes(),
      ]).timeout(const Duration(seconds: 6));

      _stats = results[0] as SystemStats;
      _srtData = results[1] as SrtInboundPayload;
      _routes = results[2] as List<RouteModel>;
      _isConnected = true;
      _lastError = null;
      _lastSyncTime = DateTime.now();
    } catch (e) {
      _isConnected = false;
      _lastError = e.toString();
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<bool> startRoute(String routeId) async {
    final ok = await _apiClient.startRoute(routeId);
    if (ok) await refreshAll(silent: true);
    return ok;
  }

  Future<bool> stopRoute(String routeId) async {
    final ok = await _apiClient.stopRoute(routeId);
    if (ok) await refreshAll(silent: true);
    return ok;
  }

  Future<bool> switchRouteSource(String routeId, String source) async {
    final ok = await _apiClient.switchRouteSource(routeId, source);
    if (ok) await refreshAll(silent: true);
    return ok;
  }

  Future<Map<String, dynamic>> testConnection(ServerConfig testCfg) {
    return _apiClient.testConnection(testCfg);
  }

  ApiClient get apiClient => _apiClient;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
