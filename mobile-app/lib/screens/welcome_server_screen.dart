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

  late TextEditingController _hostController;
  late TextEditingController _httpPortController;
  late TextEditingController _srtPortController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  bool _useHttps = false;
  bool _obscurePassword = true;

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
    _userController = TextEditingController(text: currentConfig.username.isNotEmpty ? currentConfig.username : 'admin');
    _passController = TextEditingController(text: currentConfig.password);
    _useHttps = currentConfig.useHttps;

    // Listen to changes so Tab 2 (Tata Cara) updates URLs dynamically in real-time
    _hostController.addListener(_onFormChanged);
    _httpPortController.addListener(_onFormChanged);
    _srtPortController.addListener(_onFormChanged);
  }

  void _onFormChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostController.removeListener(_onFormChanged);
    _httpPortController.removeListener(_onFormChanged);
    _srtPortController.removeListener(_onFormChanged);
    _hostController.dispose();
    _httpPortController.dispose();
    _srtPortController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  String get _currentHost => _hostController.text.trim();
  String get _currentHttpPort => _httpPortController.text.trim().isNotEmpty ? _httpPortController.text.trim() : '8080';
  String get _currentSrtPort => _srtPortController.text.trim().isNotEmpty ? _srtPortController.text.trim() : '8890';
  bool get _hasHost => _currentHost.isNotEmpty;
  String get _displayHost => _hasHost ? _currentHost : '[MASUKKAN_IP_SERVER]';
  String get _displayScheme => _useHttps ? 'https' : 'http';

  ServerConfig _getConfigFromForm() {
    return ServerConfig(
      host: _currentHost,
      httpPort: int.tryParse(_currentHttpPort) ?? 8080,
      srtPort: int.tryParse(_currentSrtPort) ?? 8890,
      username: _userController.text.trim(),
      password: _passController.text.trim(),
      useHttps: _useHttps,
    );
  }

  Future<void> _testConnection() async {
    if (!_hasHost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: MakasnaTheme.amber,
          content: Text('Silakan masukkan alamat IP / Hostname server terlebih dahulu'),
        ),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = null;
      _testSuccess = null;
    });

    final cfg = _getConfigFromForm();
    final res = await context.read<GatewayProvider>().testConnection(cfg);

    setState(() {
      _isTesting = false;
      _testSuccess = res['success'] == true;
      if (res['success'] == true) {
        _testMessage = 'Koneksi sukses terhubung ke $_currentHost! Latensi: ${res['latency_ms']} ms';
      } else {
        _testMessage = res['message'] ?? 'Koneksi ke server gagal. Periksa IP dan Port.';
      }
    });
  }

  Future<void> _connectAndProceed() async {
    if (!_hasHost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: MakasnaTheme.red,
          content: Text('Alamat IP server wajib diisi untuk membuka remote!'),
        ),
      );
      return;
    }

    final cfg = _getConfigFromForm();
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
                    fontSize: 13,
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: MakasnaTheme.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1019),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hasHost ? MakasnaTheme.border : MakasnaTheme.amber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: TextStyle(
                      color: _hasHost ? MakasnaTheme.cyan : MakasnaTheme.amber,
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      fontWeight: _hasHost ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                ),
                if (copyable) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      if (!_hasHost) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: MakasnaTheme.amber,
                            content: Text('Silakan masukkan IP server Anda pada tab "1. INPUT SERVER" terlebih dahulu.'),
                          ),
                        );
                        return;
                      }
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('URL berhasil disalin ke clipboard!'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.copy, size: 14, color: MakasnaTheme.textSecondary),
                    ),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/logo.png',
                width: 26,
                height: 26,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MAKASNA REMOTE',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                ),
                Text(
                  'Broadcast Video Transport',
                  style: TextStyle(fontSize: 10, color: MakasnaTheme.cyan, letterSpacing: 0.3),
                ),
              ],
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: MakasnaTheme.cyan,
          labelColor: MakasnaTheme.cyan,
          unselectedLabelColor: MakasnaTheme.textDim,
          tabs: const [
            Tab(icon: Icon(Icons.dns_outlined, size: 18), text: '1. INPUT SERVER'),
            Tab(icon: Icon(Icons.menu_book_outlined, size: 18), text: '2. TATA CARA SERVER'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ========================================================
          // TAB 1: INPUT SERVER (BEBAS TANPA SARAN SERVER)
          // ========================================================
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand Header Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MakasnaTheme.panelElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MakasnaTheme.border),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'KONEKSI REMOTE SERVER',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Masukkan alamat IP dan Port server gateway Anda sendiri untuk memulai remote control siaran.',
                              style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 11.5, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Form Fields
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MakasnaTheme.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MakasnaTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Field 1: Server IP / Hostname
                      const Text(
                        'ALAMAT IP / HOSTNAME SERVER *',
                        style: TextStyle(color: MakasnaTheme.cyan, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _hostController,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'Masukkan IP server (cth: 103.177.96.62)',
                          hintStyle: const TextStyle(color: MakasnaTheme.textDim, fontSize: 12.5),
                          prefixIcon: const Icon(Icons.dns, size: 18, color: MakasnaTheme.cyan),
                          suffixIcon: _hostController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16, color: MakasnaTheme.textDim),
                                  onPressed: () {
                                    _hostController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Field 2 & 3: Ports Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PORT API / HTTP',
                                  style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _httpPortController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                                  decoration: const InputDecoration(
                                    hintText: '8080',
                                    prefixIcon: Icon(Icons.api, size: 16, color: MakasnaTheme.textDim),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PORT SRT STREAM',
                                  style: TextStyle(color: MakasnaTheme.blueLight, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _srtPortController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                                  decoration: const InputDecoration(
                                    hintText: '8890',
                                    prefixIcon: Icon(Icons.cell_tower, size: 16, color: MakasnaTheme.blueLight),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Field 4 & 5: Credentials
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'USERNAME',
                                  style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _userController,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: const InputDecoration(
                                    hintText: 'admin',
                                    prefixIcon: Icon(Icons.person_outline, size: 16, color: MakasnaTheme.textDim),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PASSWORD',
                                  style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _passController,
                                  obscureText: _obscurePassword,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'password',
                                    prefixIcon: const Icon(Icons.lock_outline, size: 16, color: MakasnaTheme.textDim),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                        size: 16,
                                        color: MakasnaTheme.textDim,
                                      ),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // HTTPS Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Gunakan HTTPS (SSL)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              Text('Aktifkan jika menggunakan domain SSL', style: TextStyle(color: MakasnaTheme.textDim, fontSize: 10.5)),
                            ],
                          ),
                          Switch(
                            value: _useHttps,
                            activeColor: MakasnaTheme.cyan,
                            onChanged: (val) => setState(() => _useHttps = val),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Live Dynamic Endpoints Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _hasHost ? MakasnaTheme.cyan.withOpacity(0.3) : MakasnaTheme.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _hasHost ? Icons.check_circle_outline : Icons.info_outline,
                            size: 14,
                            color: _hasHost ? MakasnaTheme.cyan : MakasnaTheme.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _hasHost ? 'LIVE ENDPOINT PREVIEW' : 'MENUNGGU INPUT IP SERVER',
                            style: TextStyle(
                              color: _hasHost ? MakasnaTheme.cyan : MakasnaTheme.amber,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'API Endpoint: $_displayScheme://$_displayHost:$_currentHttpPort',
                        style: TextStyle(
                          color: _hasHost ? Colors.white70 : MakasnaTheme.textDim,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SRT Stream : srt://$_displayHost:$_currentSrtPort',
                        style: TextStyle(
                          color: _hasHost ? MakasnaTheme.blueLight : MakasnaTheme.textDim,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Test Connection Feedback Message
                if (_testMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _testSuccess == true ? MakasnaTheme.greenDim : MakasnaTheme.redDim,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _testSuccess == true ? MakasnaTheme.green : MakasnaTheme.red,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testSuccess == true ? Icons.check_circle : Icons.error_outline,
                          size: 16,
                          color: _testSuccess == true ? MakasnaTheme.green : MakasnaTheme.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testMessage!,
                            style: TextStyle(
                              color: _testSuccess == true ? Colors.white : const Color(0xFFFFB3B3),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Action Button 1: Test Connection
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MakasnaTheme.cyan,
                    side: const BorderSide(color: MakasnaTheme.cyan),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: MakasnaTheme.cyan),
                        )
                      : const Icon(Icons.network_check, size: 18),
                  label: Text(_isTesting ? 'MENGHUBUNGI SERVER...' : 'UJI KONEKSI (PING)'),
                ),
                const SizedBox(height: 10),

                // Action Button 2: Connect & Proceed
                ElevatedButton.icon(
                  onPressed: _connectAndProceed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MakasnaTheme.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.black),
                  label: const Text(
                    'HUBUNGKAN & BUKA REMOTE SERVER',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Switch to Tab 2
                Center(
                  child: TextButton.icon(
                    onPressed: () => _tabController.animateTo(1),
                    icon: const Icon(Icons.menu_book, size: 15, color: MakasnaTheme.textSecondary),
                    label: const Text(
                      'Lihat Tata Cara & Parameter URL untuk Server Ini →',
                      style: TextStyle(color: MakasnaTheme.textSecondary, fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ========================================================
          // TAB 2: TATA CARA PENGGUNAAN SERVER (DYNAMIC IP CLIENT)
          // ========================================================
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Banner: Status Server IP yang Aktif
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _hasHost ? const Color(0xFF051B24) : const Color(0xFF241A06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _hasHost ? MakasnaTheme.cyan : MakasnaTheme.amber,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _hasHost ? Icons.verified : Icons.warning_amber_rounded,
                        color: _hasHost ? MakasnaTheme.cyan : MakasnaTheme.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hasHost
                                  ? 'TARGET SERVER: $_currentHost (Port SRT: $_currentSrtPort)'
                                  : 'IP SERVER BELUM DIMASUKKAN',
                              style: TextStyle(
                                color: _hasHost ? Colors.white : MakasnaTheme.amber,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _hasHost
                                  ? 'Seluruh URL dan panduan di bawah ini otomatis menggunakan IP server yang Anda masukkan.'
                                  : 'Masukkan IP server Anda pada Tab "1. INPUT SERVER" agar URL terisi otomatis sesuai server Anda.',
                              style: const TextStyle(color: MakasnaTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

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
                      'srt://$_displayHost:$_currentSrtPort?streamid=publish:NAMA_STREAM&latency=2000000',
                    ),
                    _buildGuideRow(
                      'Format Parameter vMix (Add Input > Stream/SRT > Type: Caller):',
                      'Hostname: $_displayHost | Port: $_currentSrtPort | StreamID: publish:NAMA_STREAM',
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
                      'Hostname: $_displayHost | Port: $_currentSrtPort | StreamID: read:NAMA_STREAM',
                    ),
                    _buildGuideRow(
                      'Format Memutar di VLC Player (Media > Open Network Stream):',
                      'srt://$_displayHost:$_currentSrtPort?streamid=read:NAMA_STREAM',
                    ),
                    _buildGuideRow(
                      'Format Membuka Web Dashboard Browser:',
                      '$_displayScheme://$_displayHost:$_currentHttpPort',
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
