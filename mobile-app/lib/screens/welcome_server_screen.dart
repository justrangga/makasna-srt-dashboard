import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/server_config.dart';
import '../providers/gateway_provider.dart';
import 'home_navigation_screen.dart';

class WelcomeServerScreen extends StatefulWidget {
  final bool isSwitching;

  const WelcomeServerScreen({Key? key, this.isSwitching = false}) : super(key: key);

  @override
  State<WelcomeServerScreen> createState() => _WelcomeServerScreenState();
}

class _WelcomeServerScreenState extends State<WelcomeServerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Selected Profile: 0 = Production Default (139.190.97.109), 1 = Custom Server
  int _selectedProfileIndex = 0;

  late TextEditingController _hostController;
  late TextEditingController _httpPortController;
  late TextEditingController _srtPortController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  bool _useHttps = false;

  bool _isTesting = false;
  String? _testMessage;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final currentConfig = context.read<GatewayProvider>().config;
    _hostController = TextEditingController(text: currentConfig.host);
    _httpPortController = TextEditingController(text: currentConfig.httpPort.toString());
    _srtPortController = TextEditingController(text: currentConfig.srtPort.toString());
    _userController = TextEditingController(text: currentConfig.username);
    _passController = TextEditingController(text: currentConfig.password);
    _useHttps = currentConfig.useHttps;

    if (currentConfig.host != '139.190.97.109') {
      _selectedProfileIndex = 1;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostController.dispose();
    _httpPortController.dispose();
    _srtPortController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  ServerConfig _getActiveSelectedConfig() {
    if (_selectedProfileIndex == 0) {
      return ServerConfig(
        host: '139.190.97.109',
        httpPort: 8080,
        srtPort: 8890,
        username: _userController.text.trim().isNotEmpty ? _userController.text.trim() : 'admin',
        password: _passController.text.trim().isNotEmpty ? _passController.text.trim() : '@linux1234',
        useHttps: false,
      );
    } else {
      return ServerConfig(
        host: _hostController.text.trim(),
        httpPort: int.tryParse(_httpPortController.text.trim()) ?? 8080,
        srtPort: int.tryParse(_srtPortController.text.trim()) ?? 8890,
        username: _userController.text.trim(),
        password: _passController.text.trim(),
        useHttps: _useHttps,
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testMessage = null;
      _testSuccess = null;
    });

    final cfg = _getActiveSelectedConfig();
    final res = await context.read<GatewayProvider>().testConnection(cfg);

    setState(() {
      _isTesting = false;
      _testSuccess = res['success'] == true;
      if (res['success'] == true) {
        _testMessage = 'Terhubung ke server! Latensi: ${res['latency_ms']} ms';
      } else {
        _testMessage = res['message'] ?? 'Koneksi gagal';
      }
    });
  }

  Future<void> _connectAndProceed() async {
    final cfg = _getActiveSelectedConfig();
    await context.read<GatewayProvider>().updateConfig(cfg);

    if (mounted) {
      if (widget.isSwitching) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeNavigationScreen()),
        );
      }
    }
  }

  Widget _buildProfileCard({
    required int index,
    required String title,
    required String ip,
    required int apiPort,
    required int srtPort,
    required String tag,
    required bool isDefault,
  }) {
    final isSelected = _selectedProfileIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedProfileIndex = index;
          if (index == 0) {
            _hostController.text = '139.190.97.109';
            _httpPortController.text = '8080';
            _srtPortController.text = '8890';
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF131D2E) : MakasnaTheme.panelElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? MakasnaTheme.cyan : MakasnaTheme.border,
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: MakasnaTheme.cyan.withOpacity(0.2), blurRadius: 10)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? MakasnaTheme.cyan : MakasnaTheme.textDim,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDefault ? MakasnaTheme.cyanDim : const Color(0x26F59E0B),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isDefault ? MakasnaTheme.cyan.withOpacity(0.4) : MakasnaTheme.amber.withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: isDefault ? MakasnaTheme.cyan : MakasnaTheme.amber,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.dns, size: 14, color: MakasnaTheme.textDim),
                const SizedBox(width: 6),
                Text(
                  'IP: $ip',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 14),
                const Icon(Icons.api, size: 14, color: MakasnaTheme.textDim),
                const SizedBox(width: 4),
                Text(
                  'API: $apiPort',
                  style: const TextStyle(color: MakasnaTheme.textSecondary, fontFamily: 'monospace', fontSize: 11),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.stream, size: 14, color: MakasnaTheme.blueLight),
                const SizedBox(width: 4),
                Text(
                  'SRT: $srtPort',
                  style: const TextStyle(color: MakasnaTheme.blueLight, fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideSection(String title, IconData icon, Color iconColor, List<Widget> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MakasnaTheme.panelElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MakasnaTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: MakasnaTheme.border, height: 1),
          const SizedBox(height: 10),
          ...items,
        ],
      ),
    );
  }

  Widget _buildGuideRow(String label, String value, {bool copyable = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: MakasnaTheme.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: const TextStyle(color: MakasnaTheme.cyan, fontFamily: 'monospace', fontSize: 11.5),
                  ),
                ),
                if (copyable) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Berhasil disalin ke clipboard!'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: const Icon(Icons.copy, size: 14, color: MakasnaTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: MakasnaTheme.cyanDim,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('MAKASNA', style: TextStyle(color: MakasnaTheme.cyan, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            const Text('GATEWAY REMOTE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: MakasnaTheme.cyan,
          labelColor: MakasnaTheme.cyan,
          unselectedLabelColor: MakasnaTheme.textDim,
          tabs: const [
            Tab(icon: Icon(Icons.tune, size: 18), text: '1. PILIH SERVER'),
            Tab(icon: Icon(Icons.menu_book, size: 18), text: '2. TATA CARA SERVER'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: PILIH SERVER
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'PILIH ALAMAT SERVER YANG AKAN DI-REMOTE:',
                  style: TextStyle(
                    color: MakasnaTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),

                // Profile 1: Production Server
                _buildProfileCard(
                  index: 0,
                  title: 'Production Gateway (Server Utama)',
                  ip: '139.190.97.109',
                  apiPort: 8080,
                  srtPort: 8890,
                  tag: 'PRODUCTION',
                  isDefault: true,
                ),
                const SizedBox(height: 10),

                // Profile 2: Custom Server
                _buildProfileCard(
                  index: 1,
                  title: 'Custom Server (Input Bebas)',
                  ip: _hostController.text.isNotEmpty ? _hostController.text : 'Ganti Alamat Server',
                  apiPort: int.tryParse(_httpPortController.text) ?? 8080,
                  srtPort: int.tryParse(_srtPortController.text) ?? 8890,
                  tag: 'CUSTOM',
                  isDefault: false,
                ),
                const SizedBox(height: 16),

                // Custom Form Fields if Profile 1 selected
                if (_selectedProfileIndex == 1) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: MakasnaTheme.panelInput,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: MakasnaTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PARAMETER SERVER KUSTOM:',
                          style: TextStyle(color: MakasnaTheme.cyan, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _hostController,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'IP / HOSTNAME SERVER',
                            prefixIcon: Icon(Icons.dns, size: 16, color: MakasnaTheme.cyan),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _httpPortController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                                decoration: const InputDecoration(labelText: 'PORT API (8080)'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _srtPortController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                                decoration: const InputDecoration(labelText: 'PORT SRT (8890)'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Credentials Panel
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MakasnaTheme.panelElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MakasnaTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OTENTIKASI DASHBOARD:',
                        style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _userController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(labelText: 'Username'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _passController,
                              obscureText: true,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(labelText: 'Password'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Test Banner
                if (_testMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _testSuccess == true ? MakasnaTheme.green.withOpacity(0.15) : MakasnaTheme.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _testSuccess == true ? MakasnaTheme.green : MakasnaTheme.red),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testSuccess == true ? Icons.check_circle : Icons.error_outline,
                          color: _testSuccess == true ? MakasnaTheme.green : MakasnaTheme.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testMessage!,
                            style: TextStyle(
                              color: _testSuccess == true ? MakasnaTheme.green : MakasnaTheme.red,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Action Buttons
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MakasnaTheme.cyan,
                    side: const BorderSide(color: MakasnaTheme.cyan),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MakasnaTheme.cyan))
                      : const Icon(Icons.network_check, size: 18),
                  label: Text(_isTesting ? 'MEMERIKSA KONEKSI...' : 'UJI KONEKSI SERVER'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MakasnaTheme.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _connectAndProceed,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(
                    widget.isSwitching ? 'TERAPKAN & GANTI SERVER' : 'HUBUNGKAN & MASUK KE DASHBOARD',
                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
                  ),
                ),
              ],
            ),
          ),

          // TAB 2: TATA CARA PENGGUNAAN SERVER
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Section 1: Pengirim
                _buildGuideSection(
                  '1. CARA MENGIRIM VIDEO (KAMERA / ENCODER KE SERVER)',
                  Icons.upload,
                  MakasnaTheme.cyan,
                  [
                    const Text(
                      'Kamera atau laptop pengirim (OBS / vMix) mengirim sinyal ke server via SRT Caller:',
                      style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    _buildGuideRow(
                      'Format URL Pengirim di OBS Studio (Service: Custom):',
                      'srt://${_getActiveSelectedConfig().host}:8890?streamid=publish:NAMA_STREAM',
                    ),
                    _buildGuideRow(
                      'Format Parameter vMix (Add Input > Stream/SRT > Type: Caller):',
                      'Hostname: ${_getActiveSelectedConfig().host} | Port: 8890 | StreamID: publish:NAMA_STREAM',
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Checklist Rekomendasi Encoder Lapangan:\n'
                      '• Codec: H.264 atau H.265 (HEVC 8-bit Main Profile)\n'
                      '• Keyframe GOP: 1s atau 2s (Strict Closed GOP, Jangan Auto)\n'
                      '• B-Frames: 0 (Zero Latency Mode)\n'
                      '• Rate Control: CBR (Constant Bitrate)',
                      style: TextStyle(color: MakasnaTheme.textDim, fontSize: 11, height: 1.4),
                    ),
                  ],
                ),

                // Section 2: Penerima
                _buildGuideSection(
                  '2. CARA MENERIMA VIDEO (PC BLACKGATE / STUDIO VMIX / VLC)',
                  Icons.download,
                  MakasnaTheme.blueLight,
                  [
                    const Text(
                      'PC Studio atau laptop monitoring menarik (pull/listen) feed siaran dari server:',
                      style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    _buildGuideRow(
                      'Format Listener di vMix (Type: Caller):',
                      'Hostname: ${_getActiveSelectedConfig().host} | Port: 8890 | StreamID: read:NAMA_STREAM',
                    ),
                    _buildGuideRow(
                      'Format Memutar di VLC Player (Media > Open Network Stream):',
                      'srt://${_getActiveSelectedConfig().host}:8890?streamid=read:NAMA_STREAM',
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Catatan: Di vMix, masukkan kata "read:NAMA_STREAM" pada kolom Stream ID tanpa menulis awalan "streamid=".',
                      style: TextStyle(color: MakasnaTheme.amber, fontSize: 11),
                    ),
                  ],
                ),

                // Section 3: Master Recorder
                _buildGuideSection(
                  '3. PEREKAMAN HYPERDECK & CLOUD GOOGLE DRIVE',
                  Icons.fiber_manual_record,
                  MakasnaTheme.red,
                  [
                    const Text(
                      '• Masuk ke tab RECORDER di navigasi bawah HP.\n'
                      '• Pilih Feed Kamera pada dropdown FEED SOURCE.\n'
                      '• Pilih format rekaman: MP4 Universal atau MOV QuickTime.\n'
                      '• Tekan tombol merah RECORD untuk mulai merekam.\n'
                      '• Perekaman tidak mengganggu siaran siaran langsung utama.\n'
                      '• Setiap segmen file yang selesai otomatis tersinkronisasi ke Google Drive.',
                      style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 12, height: 1.5),
                    ),
                  ],
                ),

                // Section 4: Deteksi Audio Pecah
                _buildGuideSection(
                  '4. PEMANTAUAN AUDIO & DETEKSI SUARA PECAH',
                  Icons.volume_up,
                  MakasnaTheme.green,
                  [
                    const Text(
                      '• Perhatikan bar audio True Peak VU Meter di tab SIGNAL atau RECORDER.\n'
                      '• Jika bar menyentuh zona merah dan lampu indikator PECAH! (CLIP) menyala, berarti sinyal suara dari mic/mixer lapangan terdistorsi (overload 0 dBFS).\n'
                      '• Segera minta kru audio lapangan mengecilkan gain mixer.',
                      style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
