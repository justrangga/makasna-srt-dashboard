import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';

class PreferencesService {
  static const String _keyServerConfig = 'makasna_server_config';
  static const String _keySelectedStream = 'makasna_selected_stream';
  static const String _keyRememberSession = 'makasna_remember_session';

  Future<ServerConfig> loadServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyServerConfig);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return ServerConfig.fromJson(map);
      } catch (_) {}
    }
    return ServerConfig();
  }

  Future<void> saveServerConfig(ServerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(config.toJson());
    await prefs.setString(_keyServerConfig, raw);
  }

  Future<bool> loadRememberSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRememberSession) ?? true;
  }

  Future<void> saveRememberSession(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberSession, remember);
  }

  Future<bool> hasCachedValidSession() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_keyRememberSession) ?? true;
    if (!remember) return false;
    final raw = prefs.getString(_keyServerConfig);
    if (raw == null) return false;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final host = (map['host'] as String?)?.trim() ?? '';
      return host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyServerConfig);
    await prefs.remove(_keyRememberSession);
  }

  Future<String?> loadLastStreamId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySelectedStream);
  }

  Future<void> saveLastStreamId(String streamId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedStream, streamId);
  }
}
