import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_config.dart';
import '../models/system_stats.dart';
import '../models/srt_connection.dart';
import '../models/route_model.dart';
import '../models/recorder_state.dart';

class ApiClient {
  ServerConfig config;
  final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};
  bool _isAuthenticated = false;

  ApiClient({required this.config});

  void updateConfig(ServerConfig newConfig) {
    config = newConfig;
    _cookies.clear();
    _isAuthenticated = false;
  }

  void _extractCookies(http.Response response) {
    final rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      final parts = rawCookie.split(';');
      for (final part in parts) {
        final kv = part.trim().split('=');
        if (kv.length >= 2) {
          _cookies[kv[0]] = kv.sublist(1).join('=');
        }
      }
    }
  }

  Map<String, String> get _headers {
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (_cookies.isNotEmpty) {
      h['Cookie'] = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    return h;
  }

  Future<bool> login() async {
    try {
      final uri = Uri.parse('${config.baseUrl}/login');
      final res = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'username': config.username,
          'password': config.password,
        },
      ).timeout(Duration(seconds: config.pollIntervalSec + 3));

      _extractCookies(res);
      // Flask redirects 302 on success, or renders 200 on login page error
      if (res.statusCode == 302 || res.statusCode == 200) {
        // Verify with stats call
        final verifyRes = await _client.get(
          Uri.parse('${config.baseUrl}/api/system/stats'),
          headers: _headers,
        ).timeout(const Duration(seconds: 4));

        if (verifyRes.statusCode == 200) {
          _isAuthenticated = true;
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _ensureAuth() async {
    if (!_isAuthenticated) {
      await login();
    }
  }

  Future<SystemStats> getSystemStats() async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/system/stats');
    final res = await _client.get(uri, headers: _headers);

    if (res.statusCode == 401) {
      await login();
      final retry = await _client.get(uri, headers: _headers);
      final data = jsonDecode(retry.body) as Map<String, dynamic>;
      return SystemStats.fromJson(data['stats'] as Map<String, dynamic>? ?? {});
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return SystemStats.fromJson(data['stats'] as Map<String, dynamic>? ?? {});
  }

  Future<SrtInboundPayload> getSrtInbound() async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/srt/inbound');
    final res = await _client.get(uri, headers: _headers);

    if (res.statusCode == 401) {
      await login();
      final retry = await _client.get(uri, headers: _headers);
      final data = jsonDecode(retry.body) as Map<String, dynamic>;
      return SrtInboundPayload.fromJson(data);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return SrtInboundPayload.fromJson(data);
  }

  Future<List<RouteModel>> getRoutes() async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/routes');
    final res = await _client.get(uri, headers: _headers);

    if (res.statusCode == 401) {
      await login();
      final retry = await _client.get(uri, headers: _headers);
      final data = jsonDecode(retry.body) as Map<String, dynamic>;
      final list = (data['routes'] as List<dynamic>?) ?? [];
      return list.map((e) => RouteModel.fromJson(e as Map<String, dynamic>)).toList();
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['routes'] as List<dynamic>?) ?? [];
    return list.map((e) => RouteModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<bool> startRoute(String routeId) async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/routes/$routeId/start');
    final res = await _client.post(uri, headers: _headers);
    return res.statusCode == 200;
  }

  Future<bool> stopRoute(String routeId) async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/routes/$routeId/stop');
    final res = await _client.post(uri, headers: _headers);
    return res.statusCode == 200;
  }

  Future<bool> switchRouteSource(String routeId, String source) async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/routes/$routeId/switch-source');
    final res = await _client.post(
      uri,
      headers: _headers,
      body: jsonEncode({'source': source}),
    );
    return res.statusCode == 200;
  }

  Future<RecorderState> getRecordingStatus(String routeId) async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/routes/$routeId/record/status');
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return RecorderState.fromJson(data);
    }
    return RecorderState(active: false);
  }

  Future<bool> startRecording(String routeId, Map<String, dynamic> options) async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/routes/$routeId/record/start');
    final res = await _client.post(
      uri,
      headers: _headers,
      body: jsonEncode(options),
    );
    return res.statusCode == 200;
  }

  Future<bool> stopRecording(String routeId) async {
    await _ensureAuth();
    final uri = Uri.parse('${config.baseUrl}/api/routes/$routeId/record/stop');
    final res = await _client.post(
      uri,
      headers: _headers,
      body: jsonEncode({'route_id': routeId}),
    );
    return res.statusCode == 200;
  }

  Future<Map<String, dynamic>> testConnection(ServerConfig testCfg) async {
    final client = http.Client();
    try {
      final scheme = testCfg.useHttps ? 'https' : 'http';
      final base = '$scheme://${testCfg.host}:${testCfg.httpPort}';
      
      final stopwatch = Stopwatch()..start();
      final loginRes = await client.post(
        Uri.parse('$base/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': testCfg.username, 'password': testCfg.password},
      ).timeout(const Duration(seconds: 4));
      stopwatch.stop();

      final rawCookie = loginRes.headers['set-cookie'];
      final testHeaders = <String, String>{};
      if (rawCookie != null) {
        testHeaders['Cookie'] = rawCookie.split(';')[0];
      }

      final statsRes = await client.get(
        Uri.parse('$base/api/system/stats'),
        headers: testHeaders,
      ).timeout(const Duration(seconds: 4));

      if (statsRes.statusCode == 200) {
        return {
          'success': true,
          'latency_ms': stopwatch.elapsedMilliseconds,
          'message': 'Connected to Makasna Gateway successfully!',
        };
      } else {
        return {
          'success': false,
          'message': 'Server reached, but authentication failed (Code ${statsRes.statusCode})',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    } finally {
      client.close();
    }
  }
}
