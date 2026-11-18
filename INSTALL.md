# Instalasi Mandiri Makasna SRT Dashboard

Panduan ini memasang dashboard Flask pada Ubuntu 22.04 atau 24.04. Dashboard ini bukan MediaMTX dan bukan SLS: dashboard membaca status MediaMTX melalui API, menjalankan FFmpeg untuk route yang aktif, dan dapat menampilkan telemetri SLS jika SLS dikonfigurasi sebagai webhook.

## Arsitektur

```text
Encoder SRT  --->  MediaMTX :8890  --->  Dashboard route engine  --->  FFmpeg fan-out
                                      \
                                       --->  SLS Hub :12105 (opsional)
Browser      --->  Dashboard :8080
Dashboard    --->  MediaMTX API :9997 (lokal)
```

## 1. Prasyarat server

Gunakan server Linux dengan:

- Ubuntu 22.04 atau 24.04, arsitektur amd64 atau arm64.
- Minimal 2 vCPU, 4 GB RAM, dan ruang disk sesuai kebutuhan recording.
- IP publik atau firewall yang dapat meneruskan port UDP SRT.
- `sudo` dan akses root.
- MediaMTX yang sudah terpasang dan dapat diakses melalui API `http://127.0.0.1:9997`.
- FFmpeg 6 atau lebih baru.
- Python 3.10 atau lebih baru.

Port dashboard tidak boleh dibuka ke internet tanpa firewall atau reverse proxy. API MediaMTX `9997` sebaiknya hanya listen di localhost.

## 2. Dependensi sistem

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip ffmpeg curl jq ca-certificates
ffmpeg -version
python3 --version
```

Jika MediaMTX belum ada, ikuti dokumentasi resminya untuk versi target, lalu pastikan service aktif:

```bash
sudo systemctl enable --now mediamtx
curl -fsS http://127.0.0.1:9997/v3/paths/list
```

Jika perintah terakhir gagal, jangan lanjutkan sebelum MediaMTX API diperbaiki.

## 3. Ambil source

```bash
sudo mkdir -p /srv
sudo git clone https://github.com/justrangga/makasna-srt-dashboard.git /srv/makasna-dashboard
sudo chown -R "$USER":"$USER" /srv/makasna-dashboard
cd /srv/makasna-dashboard
```

Untuk update instalasi yang sudah ada, gunakan:

```bash
cd /srv/makasna-dashboard
sudo systemctl stop makasna-dashboard
sudo git pull --ff-only origin main
```

Jangan menjalankan `git reset --hard` pada instalasi yang memiliki `routes.json`, `events.json`, atau file runtime lokal tanpa backup.

## 4. Virtual environment dan Python dependencies

```bash
cd /srv/makasna-dashboard
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip wheel
python -m pip install -r requirements.txt
python -m compileall -q app.py
```

## 5. User service dan environment

Buat service user khusus:

```bash
sudo useradd --system --home /srv/makasna-dashboard --shell /usr/sbin/nologin makasna 2>/dev/null || true
sudo chown -R makasna:makasna /srv/makasna-dashboard
```

Buat file environment. Ganti semua nilai contoh sebelum menjalankan service:

```bash
sudo install -m 600 -o root -g root /srv/makasna-dashboard/.env.example /etc/makasna-dashboard.env
sudoedit /etc/makasna-dashboard.env
```

Contoh minimum:

```ini
PORT=8080
SECRET_KEY=generate-a-long-random-value
DASHBOARD_USER=admin
DASHBOARD_PASS=replace-with-a-unique-password
MEDIAMTX_API=http://127.0.0.1:9997
MEDIAMTX_CONF=/etc/mediamtx/mediamtx.yml
SERVER_PUBLIC_IP=203.0.113.10
```

Buat secret key tanpa menaruhnya di Git:

```bash
openssl rand -hex 32
```

`SERVER_PUBLIC_IP` boleh dikosongkan jika DNS atau autodetection digunakan, tetapi lebih baik diisi dengan IP publik yang dipakai decoder.

## 6. Install systemd service

```bash
sudo install -m 644 systemd/makasna-dashboard.service /etc/systemd/system/makasna-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable --now makasna-dashboard
sudo systemctl status makasna-dashboard --no-pager
```

Cek endpoint dan login dari mesin server:

```bash
curl -I http://127.0.0.1:8080/login
sudo journalctl -u makasna-dashboard -n 100 --no-pager
```

Buka `http://SERVER_PUBLIC_IP:8080/login` setelah port TCP 8080 diizinkan pada firewall.

## 7. Firewall dasar

Buka hanya port yang benar-benar digunakan:

```bash
sudo ufw allow 8080/tcp
sudo ufw allow 8890/udp
sudo ufw allow 12105:12150/udp   # hanya jika memakai SLS/dedicated egress
sudo ufw enable
sudo ufw status verbose
```

Jangan membuka `9997/tcp` ke publik. Jangan membuka `22/tcp` tanpa aturan sumber IP yang sesuai kebijakan server.

## 8. Konfigurasi MediaMTX minimum

Gunakan `config/mediamtx.yml.example` sebagai referensi. Nilai pentingnya adalah:

- SRT address `:8890` untuk ingest dan reader MediaMTX.
- API address `127.0.0.1:9997`.
- API harus aktif agar monitor dashboard dapat membaca koneksi.

Setelah mengubah konfigurasi:

```bash
sudo systemctl restart mediamtx
curl -fsS http://127.0.0.1:9997/v3/srtconns/list | jq .
```

## 9. Route pertama

1. Login ke dashboard.
2. Pastikan encoder mengirim ke `srt://SERVER_PUBLIC_IP:8890?streamid=publish:STREAM_NAME`.
3. Pastikan stream terlihat di panel ingest.
4. Buat route dari stream aktif.
5. Untuk egress MediaMTX biasa gunakan `read:STREAM_NAME` pada port `8890`.
6. Untuk SLS TV Pool pilih egress port `12105`.
7. Klik **Start** dan amati proses serta bitrate.
8. Saat selesai, klik **Stop** dan pastikan Active Listeners kembali kosong jika tidak ada receiver lain.

## 10. SLS Multi-Client Hub, opsional

SLS adalah komponen terpisah dari repository dashboard. Gunakan bagian ini hanya jika decoder downstream tidak mendukung Stream ID atau membutuhkan simultaneous callers.

- Hub: UDP `12105`, multi-client, empty Stream ID fallback.
- Dedicated: UDP `12106`, `12107`, dan seterusnya, 1:1.
- Webhook telemetri: `http://127.0.0.1:8080/api/sls/stat`.

Binary SLS harus dibuild dari source dengan patch khusus. Jalankan:

```bash
sudo bash scripts/patch-sls.sh
```

Script ini meng-clone `Edward-Wu/srt-live-server`, menerapkan patch (port hingga `65535`, empty Stream ID fallback `live/live/stream`, kompatibilitas GCC), build, dan memasang `/usr/local/bin/sls`. Konfigurasi `/etc/sls/sls.conf` dan unit systemd: ikuti [SLS Hub Setup](docs/wiki/SLS-Hub-Setup.md). Jangan menyalin binary dari server lain tanpa memeriksa arsitektur dan library SRT.

## 11. Backup dan update

Sebelum update:

```bash
sudo tar -C /srv -czf /root/makasna-dashboard-backup-$(date +%F).tgz \
  makasna-dashboard/routes.json \
  makasna-dashboard/events.json \
  makasna-dashboard/overlay_config.json 2>/dev/null || true
sudo cp -a /etc/makasna-dashboard.env /root/makasna-dashboard.env.backup
```

Update:

```bash
cd /srv/makasna-dashboard
sudo systemctl stop makasna-dashboard
sudo git pull --ff-only origin main
sudo -u makasna /srv/makasna-dashboard/.venv/bin/pip install -r requirements.txt
sudo systemctl start makasna-dashboard
sudo journalctl -u makasna-dashboard -n 100 --no-pager
```

## Troubleshooting cepat

**Dashboard tidak bisa dibuka**

```bash
sudo systemctl status makasna-dashboard
sudo journalctl -u makasna-dashboard -b --no-pager
sudo ss -ltnp | grep ':8080'
```

**Monitor ingest kosong**

```bash
curl -fsS http://127.0.0.1:9997/v3/srtconns/list | jq .
sudo journalctl -u mediamtx -n 100 --no-pager
```

**Route gagal start**

```bash
sudo journalctl -u makasna-dashboard -f
which ffmpeg
ffmpeg -version
```

**SLS client tidak muncul**

Pastikan route yang mengisi SLS sedang berjalan, UDP `12105` diizinkan, SLS mengirim POST ke `/api/sls/stat`, dan cek:

```bash
sudo journalctl -u sls -n 100 --no-pager
curl -fsS http://127.0.0.1:8080/api/srt/inbound
```

## File penting

- `app.py`: Flask dashboard, API, process supervision, dan route engine.
- `templates/dashboard.html`: UI dashboard.
- `requirements.txt`: Python dependencies.
- `.env.example`: template environment, bukan file secret produksi.
- `systemd/makasna-dashboard.service`: unit service dashboard.
- `config/mediamtx.yml.example`: contoh konfigurasi MediaMTX.
- `PANDUAN.md`: panduan operasional berbahasa Indonesia.
- `docs/wiki/`: dokumentasi teknis yang lebih rinci.
