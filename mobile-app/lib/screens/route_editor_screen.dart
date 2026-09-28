import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/route_model.dart';
import '../providers/gateway_provider.dart';

class RouteEditorScreen extends StatefulWidget {
  final RouteModel? route;
  final String? prefillInboundStream;

  const RouteEditorScreen({
    Key? key,
    this.route,
    this.prefillInboundStream,
  }) : super(key: key);

  @override
  State<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _DestinationItem {
  String label;
  String type; // 'srt_caller', 'srt_listener', 'rtmp'
  String url;
  String mode; // 'copy' or 'transcode'
  int videoBitrate;

  _DestinationItem({
    required this.label,
    this.type = 'srt_caller',
    required this.url,
    this.mode = 'copy',
    this.videoBitrate = 4500,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'type': type,
        'url': url,
        'mode': mode,
        'video_bitrate': videoBitrate,
        'audio_track': 0,
        'audio_codec': 'copy',
      };
}

class _RouteEditorScreenState extends State<RouteEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _descController;

  // Primary Source
  String _primaryType = 'inbound'; // 'inbound', 'srt_listener', 'srt_caller'
  late TextEditingController _pStreamIdController;
  late TextEditingController _pPortController;
  late TextEditingController _pUrlController;
  late TextEditingController _pLatencyController;
  late TextEditingController _pPassController;

  // Secondary Failover Source
  bool _secEnabled = false;
  String _secType = 'srt_listener';
  late TextEditingController _sPortController;
  late TextEditingController _sUrlController;
  late TextEditingController _sLatencyController;
  late TextEditingController _sPassController;

  // Fan-out Destinations
  final List<_DestinationItem> _destinations = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.route;

    _nameController = TextEditingController(
      text: r?.name ?? (widget.prefillInboundStream != null ? 'Rute ${widget.prefillInboundStream}' : ''),
    );
    _descController = TextEditingController(text: r?.description ?? '');

    // Primary Source initialization
    final ps = r?.primarySource ?? {};
    if (widget.prefillInboundStream != null) {
      _primaryType = 'inbound';
      _pStreamIdController = TextEditingController(text: widget.prefillInboundStream);
      _pPortController = TextEditingController(text: '12100');
      _pUrlController = TextEditingController(text: '');
    } else if (r != null) {
      final pType = ps['type']?.toString() ?? 'srt_listener';
      final pUrl = ps['url']?.toString() ?? '';
      if (pUrl.startsWith('rtsp://') || pUrl.contains(':8554/')) {
        _primaryType = 'inbound';
        final streamPart = pUrl.split('/').last.split('?').first;
        _pStreamIdController = TextEditingController(text: streamPart);
      } else {
        _primaryType = pType;
        _pStreamIdController = TextEditingController(text: ps['stream_id']?.toString() ?? '');
      }
      _pPortController = TextEditingController(text: ps['port']?.toString() ?? '12100');
      _pUrlController = TextEditingController(text: pUrl);
    } else {
      _primaryType = 'inbound';
      _pStreamIdController = TextEditingController(text: '');
      _pPortController = TextEditingController(text: '12100');
      _pUrlController = TextEditingController(text: '');
    }
    _pLatencyController = TextEditingController(text: ps['latency']?.toString() ?? '200');
    _pPassController = TextEditingController(text: ps['passphrase']?.toString() ?? '');

    // Secondary Source initialization
    final ss = r?.secondarySource ?? {};
    _secEnabled = ss['enabled'] == true;
    _secType = ss['type']?.toString() ?? 'srt_listener';
    _sPortController = TextEditingController(text: ss['port']?.toString() ?? '12101');
    _sUrlController = TextEditingController(text: ss['url']?.toString() ?? '');
    _sLatencyController = TextEditingController(text: ss['latency']?.toString() ?? '200');
    _sPassController = TextEditingController(text: ss['passphrase']?.toString() ?? '');

    // Destinations initialization
    if (r != null && r.destinations.isNotEmpty) {
      for (final d in r.destinations) {
        if (d is Map<String, dynamic>) {
          _destinations.add(
            _DestinationItem(
              label: d['label']?.toString() ?? 'Tujuan',
              type: d['type']?.toString() ?? 'srt_caller',
              url: d['url']?.toString() ?? '',
              mode: d['mode']?.toString() ?? 'copy',
              videoBitrate: int.tryParse(d['video_bitrate']?.toString() ?? '') ?? 4500,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _pStreamIdController.dispose();
    _pPortController.dispose();
    _pUrlController.dispose();
    _pLatencyController.dispose();
    _pPassController.dispose();
    _sPortController.dispose();
    _sUrlController.dispose();
    _sLatencyController.dispose();
    _sPassController.dispose();
    super.dispose();
  }

  void _addDestination() {
    showDialog(
      context: context,
      builder: (ctx) {
        String label = 'vMix Blackgate';
        String type = 'srt_caller';
        String url = 'srt://103.177.96.62:9000';
        String mode = 'copy';
        int bitrate = 4500;

        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: MakasnaTheme.panelElevated,
              title: const Text('Tambah Fan-out Tujuan', style: TextStyle(color: Colors.white, fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: label,
                      decoration: const InputDecoration(labelText: 'Label Tujuan (e.g. vMix, YouTube)'),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (val) => label = val,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: type,
                      dropdownColor: MakasnaTheme.panelElevated,
                      decoration: const InputDecoration(labelText: 'Protokol / Mode'),
                      items: const [
                        DropdownMenuItem(value: 'srt_caller', child: Text('SRT Caller (Kirim ke Remote)')),
                        DropdownMenuItem(value: 'srt_listener', child: Text('SRT Listener (Tunggu Tarikan)')),
                        DropdownMenuItem(value: 'rtmp', child: Text('RTMP Stream (YouTube/FB/Twitch)')),
                      ],
                      onChanged: (val) => setDlgState(() => type = val ?? 'srt_caller'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: url,
                      decoration: const InputDecoration(labelText: 'URL Tujuan (srt:// atau rtmp://)'),
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                      onChanged: (val) => url = val,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: mode,
                      dropdownColor: MakasnaTheme.panelElevated,
                      decoration: const InputDecoration(labelText: 'Encoding Mode'),
                      items: const [
                        DropdownMenuItem(value: 'copy', child: Text('Passthrough (Copy Asli 0% CPU)')),
                        DropdownMenuItem(value: 'transcode', child: Text('Transcode / Re-encode')),
                      ],
                      onChanged: (val) => setDlgState(() => mode = val ?? 'copy'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal', style: TextStyle(color: MakasnaTheme.textDim)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: MakasnaTheme.cyan, foregroundColor: Colors.black),
                  onPressed: () {
                    if (url.trim().isNotEmpty) {
                      setState(() {
                        _destinations.add(
                          _DestinationItem(
                            label: label.trim().isEmpty ? 'Destination' : label.trim(),
                            type: type,
                            url: url.trim(),
                            mode: mode,
                            videoBitrate: bitrate,
                          ),
                        );
                      });
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Tambah Fan-out'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final gateway = context.read<GatewayProvider>();

    try {
      // Build primary source object
      Map<String, dynamic> primarySource;
      if (_primaryType == 'inbound') {
        final streamId = _pStreamIdController.text.trim();
        primarySource = {
          'type': 'inbound',
          'url': 'rtsp://127.0.0.1:8554/$streamId',
          'stream_id': streamId,
          'latency': int.tryParse(_pLatencyController.text) ?? 200,
        };
      } else if (_primaryType == 'srt_caller') {
        primarySource = {
          'type': 'srt_caller',
          'url': _pUrlController.text.trim(),
          'latency': int.tryParse(_pLatencyController.text) ?? 200,
          'passphrase': _pPassController.text.trim(),
        };
      } else {
        primarySource = {
          'type': 'srt_listener',
          'address': '0.0.0.0',
          'port': int.tryParse(_pPortController.text) ?? 12100,
          'latency': int.tryParse(_pLatencyController.text) ?? 200,
          'passphrase': _pPassController.text.trim(),
        };
      }

      // Build secondary source object
      Map<String, dynamic> secondarySource = {
        'enabled': _secEnabled,
        'type': _secType,
        'latency': int.tryParse(_sLatencyController.text) ?? 200,
        'passphrase': _sPassController.text.trim(),
      };
      if (_secType == 'srt_caller') {
        secondarySource['url'] = _sUrlController.text.trim();
      } else {
        secondarySource['address'] = '0.0.0.0';
        secondarySource['port'] = int.tryParse(_sPortController.text) ?? 12101;
      }

      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'failover_policy': _secEnabled ? 'auto' : 'none',
        'primary_source': primarySource,
        'secondary_source': secondarySource,
        'destinations': _destinations.map((d) => d.toJson()).toList(),
      };

      bool ok = false;
      if (widget.route != null) {
        ok = await gateway.updateRoute(widget.route!.id, payload);
      } else {
        ok = await gateway.createRoute(payload);
      }

      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: MakasnaTheme.green,
              content: Text('Rute "${_nameController.text.trim()}" berhasil disimpan!'),
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: MakasnaTheme.red,
              content: Text('Gagal menyimpan rute. Periksa koneksi atau parameter rute.'),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayProvider>();
    final isEditing = widget.route != null;

    // Available inbound stream IDs
    final inboundOptions = gateway.srtData.publishers.map((p) => p.streamId).toSet().toList();
    if (_pStreamIdController.text.isNotEmpty && !inboundOptions.contains(_pStreamIdController.text)) {
      inboundOptions.add(_pStreamIdController.text);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'EDIT RUTE GATEWAY' : 'BUAT RUTE BARU'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _handleSave,
            icon: _isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: MakasnaTheme.cyan))
                : const Icon(Icons.check, color: MakasnaTheme.cyan, size: 18),
            label: Text(
              isEditing ? 'UPDATE' : 'SIMPAN',
              style: const TextStyle(color: MakasnaTheme.cyan, fontWeight: FontWeight.bold),
            ),
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
              // 1. Basic Route Info
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
                    const Text('INFORMASI RUTE', style: TextStyle(color: MakasnaTheme.cyan, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: 'Nama Rute Siaran *',
                        prefixIcon: Icon(Icons.alt_route, color: MakasnaTheme.cyan, size: 18),
                        hintText: 'e.g. Program Utama, Cam 1 Blackgate',
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Nama rute wajib diisi' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _descController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Deskripsi / Catatan Rute',
                        prefixIcon: Icon(Icons.notes, color: MakasnaTheme.textDim, size: 18),
                        hintText: 'Catatan tujuan siaran atau operator',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Primary Source Config
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MakasnaTheme.panelElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MakasnaTheme.cyan.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PRIMARY SOURCE (SUMBER UTAMA)', style: TextStyle(color: MakasnaTheme.cyan, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _primaryType,
                      dropdownColor: MakasnaTheme.panelElevated,
                      decoration: const InputDecoration(labelText: 'Tipe Sumber Input Video'),
                      items: const [
                        DropdownMenuItem(value: 'inbound', child: Text('Live Inbound SRT (Feed Sedang Masuk)')),
                        DropdownMenuItem(value: 'srt_listener', child: Text('SRT Listener (Gateway Buka Port)')),
                        DropdownMenuItem(value: 'srt_caller', child: Text('SRT Caller (Gateway Tarik dari Luar)')),
                      ],
                      onChanged: (val) => setState(() => _primaryType = val ?? 'inbound'),
                    ),
                    const SizedBox(height: 10),

                    if (_primaryType == 'inbound') ...[
                      if (inboundOptions.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: inboundOptions.contains(_pStreamIdController.text) ? _pStreamIdController.text : inboundOptions.first,
                          dropdownColor: MakasnaTheme.panelElevated,
                          decoration: const InputDecoration(
                            labelText: 'Pilih Inbound SRT Publisher Aktif',
                            prefixIcon: Icon(Icons.videocam, color: MakasnaTheme.green, size: 18),
                          ),
                          items: inboundOptions.map((s) => DropdownMenuItem(value: s, child: Text('Live Feed: $s'))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _pStreamIdController.text = val);
                          },
                        )
                      else
                        TextFormField(
                          controller: _pStreamIdController,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Nama Stream ID Feed Inbound',
                            hintText: 'e.g. MobileTest, RANS, CAM1',
                          ),
                        ),
                    ] else if (_primaryType == 'srt_listener') ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _pPortController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                              decoration: const InputDecoration(labelText: 'Port Listen SRT (e.g. 12100)'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _pLatencyController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                              decoration: const InputDecoration(labelText: 'Latency (ms)', suffixText: 'ms'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _pPassController,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                        decoration: const InputDecoration(labelText: 'Passphrase SRT (Opsional)', hintText: 'Kosongkan jika tanpa enkripsi'),
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _pUrlController,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Remote SRT URL',
                          hintText: 'srt://encoder-host:port?streamid=...',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Secondary Failover Source
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MakasnaTheme.panelElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _secEnabled ? MakasnaTheme.amber.withOpacity(0.4) : MakasnaTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'FAILOVER BACKUP (CADANGAN)',
                          style: TextStyle(color: MakasnaTheme.amber, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        Switch(
                          value: _secEnabled,
                          activeColor: MakasnaTheme.amber,
                          onChanged: (val) => setState(() => _secEnabled = val),
                        ),
                      ],
                    ),
                    if (_secEnabled) ...[
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _secType,
                        dropdownColor: MakasnaTheme.panelElevated,
                        decoration: const InputDecoration(labelText: 'Tipe Backup Source'),
                        items: const [
                          DropdownMenuItem(value: 'srt_listener', child: Text('SRT Listener (Port Cadangan)')),
                          DropdownMenuItem(value: 'srt_caller', child: Text('SRT Caller (Tarik Backup URL)')),
                        ],
                        onChanged: (val) => setState(() => _secType = val ?? 'srt_listener'),
                      ),
                      const SizedBox(height: 10),
                      if (_secType == 'srt_listener')
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _sPortController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                                decoration: const InputDecoration(labelText: 'Port Listen Cadangan (e.g. 12101)'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _sLatencyController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                                decoration: const InputDecoration(labelText: 'Latency (ms)', suffixText: 'ms'),
                              ),
                            ),
                          ],
                        )
                      else
                        TextFormField(
                          controller: _sUrlController,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                          decoration: const InputDecoration(labelText: 'URL Backup SRT', hintText: 'srt://backup-host:port'),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Destinations (Fan-outs)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MakasnaTheme.panelElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MakasnaTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'FAN-OUT TUJUAN (OUTPUTS)',
                          style: TextStyle(color: MakasnaTheme.cyan, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        TextButton.icon(
                          onPressed: _addDestination,
                          icon: const Icon(Icons.add, size: 16, color: MakasnaTheme.cyan),
                          label: const Text('Tambah Fan-out', style: TextStyle(color: MakasnaTheme.cyan, fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_destinations.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Belum ada output tujuan. Tambahkan setidaknya 1 fan-out (misal: vMix Blackgate atau YouTube).',
                          style: TextStyle(color: MakasnaTheme.textDim, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ..._destinations.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final d = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: MakasnaTheme.panelInput,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: MakasnaTheme.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: MakasnaTheme.cyanDim,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  d.type.toUpperCase().replaceAll('_', ' '),
                                  style: const TextStyle(color: MakasnaTheme.cyan, fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text(
                                      d.url,
                                      style: const TextStyle(color: MakasnaTheme.textDim, fontSize: 10, fontFamily: 'monospace'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: MakasnaTheme.red, size: 18),
                                onPressed: () => setState(() => _destinations.removeAt(idx)),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Save Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MakasnaTheme.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSaving ? null : _handleSave,
                icon: const Icon(Icons.save, size: 18),
                label: Text(
                  isEditing ? 'PERBARUI RUTE SEKARANG' : 'BUAT & SIMPAN RUTE SEKARANG',
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
