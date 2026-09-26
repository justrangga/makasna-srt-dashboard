import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/server_config.dart';
import '../providers/gateway_provider.dart';

class SettingsProfileScreen extends StatefulWidget {
  const SettingsProfileScreen({Key? key}) : super(key: key);

  @override
  State<SettingsProfileScreen> createState() => _SettingsProfileScreenState();
}

class _SettingsProfileScreenState extends State<SettingsProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _hostController;
  late TextEditingController _httpPortController;
  late TextEditingController _srtPortController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  bool _useHttps = false;
  int _pollInterval = 2;

  bool _isTesting = false;
  String? _testResultMessage;
  bool? _testResultSuccess;

  @override
  void initState() {
    super.initState();
    final config = context.read<GatewayProvider>().config;
    _hostController = TextEditingController(text: config.host);
    _httpPortController = TextEditingController(text: config.httpPort.toString());
    _srtPortController = TextEditingController(text: config.srtPort.toString());
    _userController = TextEditingController(text: config.username);
    _passController = TextEditingController(text: config.password);
    _useHttps = config.useHttps;
    _pollInterval = config.pollIntervalSec;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _httpPortController.dispose();
    _srtPortController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  ServerConfig _buildConfigFromForm() {
    return ServerConfig(
      host: _hostController.text.trim(),
      httpPort: int.tryParse(_httpPortController.text.trim()) ?? 8080,
      srtPort: int.tryParse(_srtPortController.text.trim()) ?? 8890,
      username: _userController.text.trim(),
      password: _passController.text.trim(),
      useHttps: _useHttps,
      pollIntervalSec: _pollInterval,
    );
  }

  Future<void> _handleTestConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResultMessage = null;
      _testResultSuccess = null;
    });

    final testCfg = _buildConfigFromForm();
    final res = await context.read<GatewayProvider>().testConnection(testCfg);

    setState(() {
      _isTesting = false;
      _testResultSuccess = res['success'] == true;
      if (res['success'] == true) {
        _testResultMessage = 'Koneksi Sukses! Latensi: ${res['latency_ms']} ms';
      } else {
        _testResultMessage = res['message'] ?? 'Gagal menghubungi gateway';
      }
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    final newConfig = _buildConfigFromForm();

    await context.read<GatewayProvider>().updateConfig(newConfig);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: MakasnaTheme.green,
          content: Text('Konfigurasi server berhasil disimpan & dimuat ulang!'),
        ),
      );
      Navigator.pop(context);
    }
  }

  void _resetToDefault() {
    setState(() {
      _hostController.text = '139.190.97.109';
      _httpPortController.text = '8080';
      _srtPortController.text = '8890';
      _userController.text = 'admin';
      _passController.text = '@linux1234';
      _useHttps = false;
      _pollInterval = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GATEWAY SERVER PROFILE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore, color: MakasnaTheme.textSecondary),
            tooltip: 'Reset Default Server',
            onPressed: _resetToDefault,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MakasnaTheme.panelElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MakasnaTheme.cyan.withOpacity(0.3)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.tune, color: MakasnaTheme.cyan, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ubah IP dan Port kapan saja ketika server berganti alamat. Aplikasi akan otomatis terhubung ke alamat baru.',
                        style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Server Host / IP
              TextFormField(
                controller: _hostController,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'SERVER IP / HOSTNAME',
                  hintText: 'e.g. 139.190.97.109 atau stream.makasna.com',
                  prefixIcon: Icon(Icons.dns_outlined, color: MakasnaTheme.cyan, size: 18),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Server IP tidak boleh kosong' : null,
              ),
              const SizedBox(height: 14),

              // Ports Row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _httpPortController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'API PORT',
                        hintText: '8080',
                        prefixIcon: Icon(Icons.api_outlined, color: MakasnaTheme.cyan, size: 18),
                      ),
                      validator: (v) => v == null || int.tryParse(v) == null ? 'Port salah' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _srtPortController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'SRT PORT',
                        hintText: '8890',
                        prefixIcon: Icon(Icons.stream, color: MakasnaTheme.blueLight, size: 18),
                      ),
                      validator: (v) => v == null || int.tryParse(v) == null ? 'Port salah' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // HTTPS Switch
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gunakan Koneksi Aman HTTPS', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Aktifkan jika gateway menggunakan sertifikat SSL', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 11)),
                value: _useHttps,
                activeColor: MakasnaTheme.cyan,
                onChanged: (val) => setState(() => _useHttps = val),
              ),
              const Divider(color: MakasnaTheme.border),
              const SizedBox(height: 8),

              // Credentials
              TextFormField(
                controller: _userController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'USERNAME DASHBOARD',
                  prefixIcon: Icon(Icons.person_outline, color: MakasnaTheme.textSecondary, size: 18),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Username wajib diisi' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'PASSWORD DASHBOARD',
                  prefixIcon: Icon(Icons.lock_outline, color: MakasnaTheme.textSecondary, size: 18),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Password wajib diisi' : null,
              ),
              const SizedBox(height: 20),

              // Test Result Banner
              if (_testResultMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _testResultSuccess == true
                        ? MakasnaTheme.green.withOpacity(0.15)
                        : MakasnaTheme.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _testResultSuccess == true ? MakasnaTheme.green : MakasnaTheme.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testResultSuccess == true ? Icons.check_circle : Icons.error_outline,
                        color: _testResultSuccess == true ? MakasnaTheme.green : MakasnaTheme.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResultMessage!,
                          style: TextStyle(
                            color: _testResultSuccess == true ? MakasnaTheme.green : MakasnaTheme.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: MakasnaTheme.cyan,
                  side: const BorderSide(color: MakasnaTheme.cyan),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isTesting ? null : _handleTestConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: MakasnaTheme.cyan),
                      )
                    : const Icon(Icons.network_check, size: 18),
                label: Text(_isTesting ? 'MEMERIKSA KONEKSI...' : 'UJI KONEKSI SERVER'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MakasnaTheme.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _handleSave,
                icon: const Icon(Icons.save, size: 18),
                label: const Text(
                  'SIMPAN & TERAPKAN PROFILE',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
