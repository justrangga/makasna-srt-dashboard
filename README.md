# Makasna SRT Dashboard

[Bahasa Indonesia](#bahasa-indonesia) | [English](#english)

---

<a id="bahasa-indonesia"></a>
## Bahasa Indonesia

### Ringkasan dan fitur

Makasna SRT Dashboard adalah dasbor Flask ringan untuk memantau MediaMTX dan mengelola tujuan relay SRT/RTMP berbasis FFmpeg.

- Statistik resource host dan stream aktif dari MediaMTX Control API
- Sumber SRT, RTSP, RTMP, dan HTTP
- Tujuan relay SRT, RTMP, dan RTMPS
- Deteksi dan pemilihan track audio dengan `ffprobe`
- Restart otomatis FFmpeg selama tujuan tetap aktif
- Definisi relay persisten di `forwards.json` dan log per relay di `logs/`
- Mode **Direct Copy** dan transkode H.264/AAC dengan bitrate khusus

### Arsitektur

Publisher mengirim stream ke MediaMTX. Dasbor meminta status dari Control API lokal MediaMTX di `127.0.0.1:9997` dan menjalankan satu proses FFmpeg untuk setiap tujuan aktif. Nama sumber lokal seperti `live` diubah menjadi `rtsp://127.0.0.1:8554/live`. `forwards.json` dan `logs/` adalah data runtime yang diabaikan Git.

Untuk produksi, unit yang disediakan menjalankan:

- MediaMTX sebagai user `mediamtx`, memakai konfigurasi dari `/etc/mediamtx.env`.
- Gunicorn sebagai user `makasna`, satu worker di `127.0.0.1:${PORT}`. Satu worker wajib karena status proses relay disimpan di memori.

### Kebutuhan

- Linux untuk contoh systemd di bawah
- Git
- Python 3.9 atau lebih baru, termasuk dukungan `venv`
- FFmpeg dan `ffprobe`
- MediaMTX yang mendukung key pada `config/mediamtx.yml.example`
- Hak root hanya untuk instalasi paket, binary, user, konfigurasi `/etc`, dan service
- User service non-root untuk operasi normal

Contoh instalasi paket pada Debian/Ubuntu:

```sh
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip ffmpeg
```

### Clone dan instal dependensi

```sh
git clone https://github.com/justrangga/makasna-srt-dashboard.git
cd makasna-srt-dashboard
./deploy.sh
```

`deploy.sh` hanya membuat `.venv`, memperbarui pip, dan memasang `requirements.txt`. Script ini **tidak** memasang MediaMTX, menyalin konfigurasi, membuat user, atau memasang/mengaktifkan/me-restart service systemd.

Alternatif manual:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### Menyiapkan MediaMTX

1. Unduh binary MediaMTX yang sesuai dari rilis resmi proyek MediaMTX dan verifikasi checksum rilisnya.
2. Pasang binary sebagai `/usr/local/bin/mediamtx` dan pastikan executable:

   ```sh
   sudo install -o root -g root -m 0755 PATH_TO_MEDIAMTX_BINARY /usr/local/bin/mediamtx
   ```

3. Untuk pengembangan, salin konfigurasi contoh:

   ```sh
   cp config/mediamtx.yml.example config/mediamtx.yml
   mediamtx config/mediamtx.yml
   ```

Konfigurasi contoh mengaktifkan SRT pada UDP `8890`, RTSP/TCP pada `8554`, RTMP/TCP pada `1935`, dan Control API hanya pada `127.0.0.1:9997`. HLS, WebRTC, metrics, pprof, playback, dan recording dinonaktifkan. Konfigurasi ini menerima publish/read anonim pada path apa pun; batasi autentikasi dan jaringan sebelum dipaparkan ke jaringan yang tidak dipercaya.

### Konfigurasi environment

Salin contoh lokal:

```sh
cp .env.example .env
```

Buat `SECRET_KEY` secara aman dengan generator kriptografis Python; jangan memakai nilai contoh:

```sh
python3 -c 'import secrets; print(secrets.token_hex(32))'
```

Masukkan hasilnya ke `.env` tanpa tanda kutip:

```text
PORT=8080
SECRET_KEY=PASTE_GENERATED_VALUE_HERE
```

Aplikasi tidak memuat `.env` secara otomatis. Ekspor isinya sebelum startup pengembangan:

```sh
set -a
. ./.env
set +a
```

Jika `SECRET_KEY` tidak tersedia, aplikasi membuat nilai acak per proses sehingga session tidak bertahan setelah restart. Saat ini dasbor tidak memiliki login bawaan.

### Menjalankan pengembangan

Jalankan MediaMTX di terminal pertama seperti di atas. Di terminal kedua:

```sh
. .venv/bin/activate
set -a
. ./.env
set +a
python app.py
```

Server pengembangan Flask mendengarkan `0.0.0.0:${PORT}` (default `8080`). Gunakan hanya untuk pengembangan dan batasi akses dengan firewall.

### Setup produksi dengan systemd

Perintah berikut sesuai dengan path dan user pada template saat ini. Ganti `REPOSITORY_DIR` dengan direktori clone lokal yang sebenarnya.

```sh
sudo useradd --system --home /nonexistent --shell /usr/sbin/nologin mediamtx
sudo useradd --system --home /srv/makasna-dashboard --shell /usr/sbin/nologin makasna
sudo mkdir -p /etc/mediamtx /srv/makasna-dashboard
sudo cp -a REPOSITORY_DIR/. /srv/makasna-dashboard/
sudo chown -R makasna:makasna /srv/makasna-dashboard
sudo -u makasna /srv/makasna-dashboard/deploy.sh
sudo install -o root -g root -m 0644 /srv/makasna-dashboard/config/mediamtx.yml.example /etc/mediamtx/mediamtx.yml
```

Buat environment MediaMTX:

```sh
printf '%s\n' 'MEDIAMTX_CONFIG=/etc/mediamtx/mediamtx.yml' | sudo tee /etc/mediamtx.env >/dev/null
sudo chmod 0600 /etc/mediamtx.env
```

Buat environment dasbor dengan secret baru tanpa mencetak secret ke terminal:

```sh
SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
printf 'PORT=8080\nSECRET_KEY=%s\n' "$SECRET_KEY" | sudo tee /etc/makasna-dashboard.env >/dev/null
unset SECRET_KEY
sudo chmod 0600 /etc/makasna-dashboard.env
```

Pasang template unit tanpa modifikasi jika path di atas digunakan:

```sh
sudo install -o root -g root -m 0644 /srv/makasna-dashboard/systemd/mediamtx.service /etc/systemd/system/mediamtx.service
sudo install -o root -g root -m 0644 /srv/makasna-dashboard/systemd/makasna-dashboard.service /etc/systemd/system/makasna-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable --now mediamtx.service
sudo systemctl enable --now makasna-dashboard.service
sudo systemctl status mediamtx.service makasna-dashboard.service
```

Dasbor produksi hanya mendengarkan localhost. Untuk akses remote, letakkan reverse proxy HTTPS dengan autentikasi di depan `127.0.0.1:8080`; jangan mengubah binding menjadi publik tanpa kontrol akses.

### Publish dan read SRT

Ganti `SERVER_IP` dan `STREAM_NAME`; jangan menaruh stream key nyata di dokumentasi atau source control.

Publish dari OBS, kamera, atau encoder:

```text
srt://SERVER_IP:8890?streamid=publish:STREAM_NAME
```

Read dari VLC, OBS, vMix, atau receiver lain:

```text
srt://SERVER_IP:8890?streamid=read:STREAM_NAME
```

Contoh FFmpeg dengan placeholder:

```sh
ffmpeg -re -i INPUT_FILE -c copy -f mpegts 'srt://SERVER_IP:8890?streamid=publish:STREAM_NAME'
ffplay 'srt://SERVER_IP:8890?streamid=read:STREAM_NAME'
```

### Menambah relay dan memilih audio multitrack

1. Pastikan source sedang aktif.
2. Buka dasbor dan pilih **Add Redirect Target**.
3. Isi label, lalu isi nama stream lokal seperti `live` atau URL lengkap `rtsp://`, `rtmp://`, `srt://`, atau `http://`.
4. Klik **Detect Audio Tracks**. Dasbor menjalankan `ffprobe` dan menampilkan codec, channel, sample rate, bahasa, dan judul jika tersedia.
5. Pilih track yang diperlukan. Pilihan adalah indeks audio berbasis nol: “Audio 1” memetakan `0:a:0?`, “Audio 2” memetakan `0:a:1?`, dan seterusnya. Video pertama dipetakan sebagai `0:v:0?`.
6. Isi URL tujuan SRT/RTMP/RTMPS hanya melalui UI atau storage rahasia, pilih mode, lalu **Save & Start**.
7. Gunakan **Stop/Start**, **Logs**, atau hapus relay dari tabel. Relay yang tetap aktif dicoba ulang tiga detik setelah FFmpeg berhenti; relay aktif juga dimulai kembali saat `python app.py` memanggil bootstrap. Unit Gunicorn saat ini tidak memanggil bootstrap aplikasi secara eksplisit, jadi periksa dan aktifkan relay dari UI setelah restart service.

Jika deteksi gagal, uji source dari host yang sama:

```sh
ffprobe -v error -show_streams 'SOURCE_URL'
```

### Direct Copy dan Custom Bitrate

- **Direct Copy** memakai `-c:v copy -c:a copy`: CPU rendah, codec dan bitrate asli dipertahankan, tetapi destination harus mendukung codec tersebut dan bitrate tidak dapat diubah.
- **Custom Bitrate** meng-encode video dengan `libx264` dan audio dengan AAC. UI mengatur video bitrate, max bitrate, buffer, audio bitrate, dan preset encoder. Mode ini memakai lebih banyak CPU dan tidak mengubah resolusi atau frame rate.

### Test dan validasi

Dari root repository dengan virtual environment aktif:

```sh
. .venv/bin/activate
python -m unittest discover -s tests -v
python -m py_compile app.py tests/test_app.py
sh -n deploy.sh
```

Test menggunakan data runtime sementara dan mock startup relay; test tidak menghubungi sistem produksi.

### Prosedur update

Backup data runtime dan konfigurasi lokal secara aman, lalu update sebagai user yang memiliki checkout:

```sh
cd /srv/makasna-dashboard
cp forwards.json /SAFE_BACKUP_PATH/forwards.json
cp /etc/makasna-dashboard.env /SAFE_BACKUP_PATH/makasna-dashboard.env
cp /etc/mediamtx/mediamtx.yml /SAFE_BACKUP_PATH/mediamtx.yml
git pull --ff-only
sudo -u makasna ./deploy.sh
```

Tinjau perubahan pada `.env.example`, konfigurasi MediaMTX, dan template systemd. Salin perubahan template/config secara manual hanya setelah membandingkannya; `deploy.sh` tidak melakukannya. Kemudian:

```sh
sudo systemctl daemon-reload
sudo systemctl restart mediamtx.service makasna-dashboard.service
sudo systemctl status mediamtx.service makasna-dashboard.service
```

Pastikan ownership `forwards.json` dan `logs/` tetap `makasna:makasna`. Uji publish/read dan relay setelah update.

### Firewall dan port jaringan

Buka hanya protokol yang benar-benar digunakan:

| Port | Protokol | Fungsi | Paparan yang disarankan |
|---|---|---|---|
| `8890` | UDP | SRT publish/read | Hanya IP publisher/reader yang diperlukan |
| `8554` | TCP | RTSP | Privat/lokal kecuali memang dibutuhkan remote |
| `1935` | TCP | RTMP | Hanya jika ingest/read RTMP diperlukan |
| `9997` | TCP | MediaMTX Control API | Localhost saja; jangan dibuka di firewall |
| `8080` | TCP | Flask dev; upstream Gunicorn | Localhost/reverse proxy saja pada produksi |
| `443` | TCP | Reverse proxy HTTPS opsional | Klien dasbor yang diizinkan |

Contoh UFW untuk SRT dari satu jaringan tepercaya (sesuaikan CIDR):

```sh
sudo ufw allow from TRUSTED_CIDR to any port 8890 proto udp
```

Relay keluar juga memerlukan DNS dan akses egress ke host/port tujuan. SRT memakai UDP; aturan TCP saja tidak cukup.

### Pemecahan masalah

- **Dasbor tidak melihat stream:** periksa `systemctl status mediamtx`, lalu `curl http://127.0.0.1:9997/v3/paths/list`; pastikan `apiAddress` tetap `127.0.0.1:9997`.
- **SRT tidak tersambung:** pastikan UDP `8890` terbuka, `STREAM_NAME` sama, mode streamid adalah `publish:` atau `read:`, dan tidak ada publisher kedua karena `overridePublisher: no`.
- **Relay berhenti/gagal:** buka log dari UI atau periksa `logs/relay_RELAY_ID.log`; verifikasi URL tujuan, konektivitas egress, codec destination, dan kapasitas CPU.
- **Audio salah/hilang:** aktifkan source sebelum deteksi, jalankan `ffprobe`, lalu pilih indeks audio yang benar. Mapping bertanda `?`, jadi track yang tidak tersedia tidak membuat konstruksi command gagal.
- **Service gagal start:** jalankan `journalctl -u mediamtx.service -u makasna-dashboard.service -n 100 --no-pager`; periksa user, permission, binary, working directory, dan file environment.
- **Perubahan relay hilang/tidak dapat disimpan:** pastikan `/srv/makasna-dashboard`, `forwards.json`, dan `logs/` dapat ditulis user `makasna`.
- **UI tanpa styling/chart:** aset frontend dimuat dari CDN, sehingga browser memerlukan akses keluar atau aset harus di-host sendiri.

### Catatan keamanan

- Jangan commit `.env`, `forwards.json`, log, sertifikat, private key, password, token, stream key, atau URL tujuan/source yang mengandung kredensial.
- Perlakukan tujuan relay, command line FFmpeg, dan log sebagai data sensitif.
- Dasbor tidak memiliki autentikasi dan menyediakan operasi relay; simpan di localhost atau lindungi dengan reverse proxy HTTPS terautentikasi.
- Simpan Control API MediaMTX di localhost dan batasi publish/read anonim dengan autentikasi MediaMTX atau filtering jaringan.
- Jalankan kedua service dengan user khusus non-root dan batasi direktori yang dapat ditulis.
- Pin/validasi sumber binary MediaMTX dan update dependency secara terencana.
- Rotasi segera kredensial yang pernah masuk source control, output terminal bersama, atau log.

### Lisensi

MIT. Lihat [LICENSE](LICENSE).

---

<a id="english"></a>
## English

### Overview and features

Makasna SRT Dashboard is a lightweight Flask dashboard for monitoring MediaMTX and managing FFmpeg-based SRT/RTMP relay destinations.

- Host resource statistics and active streams from the MediaMTX Control API
- SRT, RTSP, RTMP, and HTTP sources
- SRT, RTMP, and RTMPS relay destinations
- Audio-track detection and selection with `ffprobe`
- Automatic FFmpeg restart while a destination remains enabled
- Persistent relay definitions in `forwards.json` and per-relay logs in `logs/`
- **Direct Copy** and configurable H.264/AAC bitrate modes

### Architecture

Publishers send streams to MediaMTX. The dashboard requests status from the local MediaMTX Control API at `127.0.0.1:9997` and runs one FFmpeg process for every enabled destination. A local source name such as `live` becomes `rtsp://127.0.0.1:8554/live`. `forwards.json` and `logs/` are Git-ignored runtime data.

In production, the supplied units run:

- MediaMTX as user `mediamtx`, with its configuration selected by `/etc/mediamtx.env`.
- Gunicorn as user `makasna`, with one worker on `127.0.0.1:${PORT}`. One worker is required because relay process state is held in memory.

### Requirements

- Linux for the systemd example below
- Git
- Python 3.9 or newer, including `venv` support
- FFmpeg and `ffprobe`
- A MediaMTX release supporting the keys in `config/mediamtx.yml.example`
- Root privileges only for package, binary, user, `/etc` configuration, and service installation
- Non-root service accounts for normal operation

Example package installation on Debian/Ubuntu:

```sh
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip ffmpeg
```

### Clone and install dependencies

```sh
git clone https://github.com/justrangga/makasna-srt-dashboard.git
cd makasna-srt-dashboard
./deploy.sh
```

`deploy.sh` only creates `.venv`, upgrades pip, and installs `requirements.txt`. It does **not** install MediaMTX, copy configuration, create users, or install/enable/restart systemd services.

Manual alternative:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### MediaMTX setup

1. Download the appropriate MediaMTX binary from the official MediaMTX project releases and verify its release checksum.
2. Install the binary as `/usr/local/bin/mediamtx` and make it executable:

   ```sh
   sudo install -o root -g root -m 0755 PATH_TO_MEDIAMTX_BINARY /usr/local/bin/mediamtx
   ```

3. For development, copy the example configuration:

   ```sh
   cp config/mediamtx.yml.example config/mediamtx.yml
   mediamtx config/mediamtx.yml
   ```

The example configuration enables SRT on UDP `8890`, RTSP/TCP on `8554`, RTMP/TCP on `1935`, and the Control API only on `127.0.0.1:9997`. HLS, WebRTC, metrics, pprof, playback, and recording are disabled. It accepts anonymous publishing and reading on any path; restrict authentication and network access before exposing it to an untrusted network.

### Environment configuration

Copy the local example:

```sh
cp .env.example .env
```

Generate `SECRET_KEY` safely with Python's cryptographic generator; do not use the example value:

```sh
python3 -c 'import secrets; print(secrets.token_hex(32))'
```

Put the result in `.env` without quotes:

```text
PORT=8080
SECRET_KEY=PASTE_GENERATED_VALUE_HERE
```

The application does not load `.env` automatically. Export it before development startup:

```sh
set -a
. ./.env
set +a
```

If `SECRET_KEY` is unavailable, the application creates a random value per process, so sessions do not survive a restart. The dashboard currently has no built-in login.

### Development start

Run MediaMTX in the first terminal as shown above. In a second terminal:

```sh
. .venv/bin/activate
set -a
. ./.env
set +a
python app.py
```

The Flask development server listens on `0.0.0.0:${PORT}` (default `8080`). Use it only for development and restrict access with a firewall.

### Production systemd setup

The following commands match the paths and users in the current templates. Replace `REPOSITORY_DIR` with the actual local clone directory.

```sh
sudo useradd --system --home /nonexistent --shell /usr/sbin/nologin mediamtx
sudo useradd --system --home /srv/makasna-dashboard --shell /usr/sbin/nologin makasna
sudo mkdir -p /etc/mediamtx /srv/makasna-dashboard
sudo cp -a REPOSITORY_DIR/. /srv/makasna-dashboard/
sudo chown -R makasna:makasna /srv/makasna-dashboard
sudo -u makasna /srv/makasna-dashboard/deploy.sh
sudo install -o root -g root -m 0644 /srv/makasna-dashboard/config/mediamtx.yml.example /etc/mediamtx/mediamtx.yml
```

Create the MediaMTX environment:

```sh
printf '%s\n' 'MEDIAMTX_CONFIG=/etc/mediamtx/mediamtx.yml' | sudo tee /etc/mediamtx.env >/dev/null
sudo chmod 0600 /etc/mediamtx.env
```

Create the dashboard environment with a fresh secret without printing it to the terminal:

```sh
SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
printf 'PORT=8080\nSECRET_KEY=%s\n' "$SECRET_KEY" | sudo tee /etc/makasna-dashboard.env >/dev/null
unset SECRET_KEY
sudo chmod 0600 /etc/makasna-dashboard.env
```

Install the unit templates unchanged if you used the paths above:

```sh
sudo install -o root -g root -m 0644 /srv/makasna-dashboard/systemd/mediamtx.service /etc/systemd/system/mediamtx.service
sudo install -o root -g root -m 0644 /srv/makasna-dashboard/systemd/makasna-dashboard.service /etc/systemd/system/makasna-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable --now mediamtx.service
sudo systemctl enable --now makasna-dashboard.service
sudo systemctl status mediamtx.service makasna-dashboard.service
```

The production dashboard listens only on localhost. For remote access, put an authenticated HTTPS reverse proxy in front of `127.0.0.1:8080`; do not change the binding to public without access controls.

### SRT publish and read

Replace `SERVER_IP` and `STREAM_NAME`; never put a real stream key in documentation or source control.

Publish from OBS, a camera, or an encoder:

```text
srt://SERVER_IP:8890?streamid=publish:STREAM_NAME
```

Read from VLC, OBS, vMix, or another receiver:

```text
srt://SERVER_IP:8890?streamid=read:STREAM_NAME
```

FFmpeg examples using placeholders:

```sh
ffmpeg -re -i INPUT_FILE -c copy -f mpegts 'srt://SERVER_IP:8890?streamid=publish:STREAM_NAME'
ffplay 'srt://SERVER_IP:8890?streamid=read:STREAM_NAME'
```

### Adding a relay and selecting multitrack audio

1. Ensure the source is active.
2. Open the dashboard and select **Add Redirect Target**.
3. Enter a label, then a local stream name such as `live` or a complete `rtsp://`, `rtmp://`, `srt://`, or `http://` URL.
4. Select **Detect Audio Tracks**. The dashboard runs `ffprobe` and displays codec, channels, sample rate, language, and title when available.
5. Select the required track. Selection uses a zero-based audio index: “Audio 1” maps `0:a:0?`, “Audio 2” maps `0:a:1?`, and so on. The first video maps as `0:v:0?`.
6. Enter the SRT/RTMP/RTMPS destination URL only through the UI or secret storage, choose a mode, then select **Save & Start**.
7. Use **Stop/Start**, **Logs**, or delete the relay from the table. An enabled relay retries three seconds after FFmpeg exits; enabled relays are also restarted when `python app.py` invokes bootstrap. The current Gunicorn unit does not explicitly invoke application bootstrap, so inspect and enable relays from the UI after a service restart.

If detection fails, test the source from the same host:

```sh
ffprobe -v error -show_streams 'SOURCE_URL'
```

### Direct Copy versus Custom Bitrate

- **Direct Copy** uses `-c:v copy -c:a copy`: low CPU usage, original codecs and bitrate, but the destination must support those codecs and bitrate cannot be changed.
- **Custom Bitrate** encodes video with `libx264` and audio with AAC. The UI controls video bitrate, maximum bitrate, buffer, audio bitrate, and encoder preset. It costs more CPU and does not change resolution or frame rate.

### Tests and validation

From the repository root with the virtual environment active:

```sh
. .venv/bin/activate
python -m unittest discover -s tests -v
python -m py_compile app.py tests/test_app.py
sh -n deploy.sh
```

Tests use temporary runtime data and mock relay startup; they do not contact production systems.

### Update procedure

Securely back up runtime data and local configuration, then update as the checkout owner:

```sh
cd /srv/makasna-dashboard
cp forwards.json /SAFE_BACKUP_PATH/forwards.json
cp /etc/makasna-dashboard.env /SAFE_BACKUP_PATH/makasna-dashboard.env
cp /etc/mediamtx/mediamtx.yml /SAFE_BACKUP_PATH/mediamtx.yml
git pull --ff-only
sudo -u makasna ./deploy.sh
```

Review changes to `.env.example`, the MediaMTX configuration, and systemd templates. Copy template/configuration changes manually only after comparing them; `deploy.sh` does not do this. Then run:

```sh
sudo systemctl daemon-reload
sudo systemctl restart mediamtx.service makasna-dashboard.service
sudo systemctl status mediamtx.service makasna-dashboard.service
```

Ensure `forwards.json` and `logs/` remain owned by `makasna:makasna`. Test publishing, reading, and relays after the update.

### Firewall and network ports

Open only the protocols you actually use:

| Port | Protocol | Purpose | Recommended exposure |
|---|---|---|---|
| `8890` | UDP | SRT publish/read | Only required publisher/reader IPs |
| `8554` | TCP | RTSP | Private/local unless remote access is required |
| `1935` | TCP | RTMP | Only if RTMP ingest/read is required |
| `9997` | TCP | MediaMTX Control API | Localhost only; do not open in the firewall |
| `8080` | TCP | Flask dev; Gunicorn upstream | Localhost/reverse proxy only in production |
| `443` | TCP | Optional HTTPS reverse proxy | Authorized dashboard clients |

Example UFW rule for SRT from one trusted network (adjust the CIDR):

```sh
sudo ufw allow from TRUSTED_CIDR to any port 8890 proto udp
```

Outbound relays also need DNS and egress access to each destination host/port. SRT uses UDP; a TCP-only rule is insufficient.

### Troubleshooting

- **Dashboard does not show streams:** check `systemctl status mediamtx`, then `curl http://127.0.0.1:9997/v3/paths/list`; ensure `apiAddress` remains `127.0.0.1:9997`.
- **SRT does not connect:** ensure UDP `8890` is open, `STREAM_NAME` matches, the streamid mode is `publish:` or `read:`, and there is no second publisher because `overridePublisher: no`.
- **Relay stops or fails:** open its log in the UI or inspect `logs/relay_RELAY_ID.log`; verify the destination URL, egress connectivity, destination codec support, and CPU capacity.
- **Wrong or missing audio:** activate the source before detection, run `ffprobe`, and select the correct audio index. Mapping is optional (`?`), so a missing track does not make command construction fail.
- **Service fails to start:** run `journalctl -u mediamtx.service -u makasna-dashboard.service -n 100 --no-pager`; inspect users, permissions, binaries, working directory, and environment files.
- **Relay changes disappear or cannot be saved:** ensure `/srv/makasna-dashboard`, `forwards.json`, and `logs/` are writable by user `makasna`.
- **UI has no styling/chart:** frontend assets load from CDNs, so the browser needs outbound access or the assets must be self-hosted.

### Security notes

- Never commit `.env`, `forwards.json`, logs, certificates, private keys, passwords, tokens, stream keys, or source/destination URLs containing credentials.
- Treat relay destinations, FFmpeg command lines, and logs as sensitive data.
- The dashboard has no authentication and can operate relays; keep it on localhost or protect it with an authenticated HTTPS reverse proxy.
- Keep the MediaMTX Control API on localhost and restrict anonymous publishing/reading with MediaMTX authentication or network filtering.
- Run both services under dedicated non-root users and limit writable directories.
- Pin/validate the MediaMTX binary source and update dependencies deliberately.
- Immediately rotate credentials that ever entered source control, shared terminal output, or logs.

### License

MIT. See [LICENSE](LICENSE).
