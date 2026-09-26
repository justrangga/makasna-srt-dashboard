import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';

class PreferencesService {
  static const String _keyServerConfig = 'makasna_server_config';
  static const String _keySelectedStream = 'makasna_selected_stream';

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

  Future<String?> loadLastStreamId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySelectedStream);
  }

  Future<void> saveLastStreamId(String streamId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedStream, streamId);
  }
}
