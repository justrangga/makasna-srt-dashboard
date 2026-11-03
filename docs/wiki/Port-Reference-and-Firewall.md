# Port Reference & Network Security

This document outlines all network ports used by Makasna Live Video Transport Gateway and firewall security group recommendations.

---

## Port Allocation Matrix

| Port | Protocol | Layer / Service | Traffic Direction | Purpose |
|:---:|:---:|:---|:---:|:---|
| **8080** | TCP | Flask Web Dashboard | Inbound | Web UI, Management REST API, HLS proxy |
| **8890** | UDP | MediaMTX SRT Core | Inbound / Bidirectional | Primary SRT Ingest (`publish:`) and Egress (`read:`) |
| **1935** | TCP | MediaMTX RTMP | Inbound | Legacy RTMP contributions |
| **8554** | TCP | MediaMTX RTSP | Inbound / Outbound | RTSP stream server |
| **8888** | TCP | MediaMTX Native HLS | Inbound | Low-latency fMP4 HLS engine |
| **8889** | TCP | WebRTC Signaler / Media | Inbound | Sub-second browser video preview |
| **9997** | TCP | MediaMTX Management API | Local Only (127.0.0.1) | Internal telemetry and path queries |
| **12105** | UDP | SLS Multi-Client Hub | Inbound / Bidirectional | Multi-receiver TV Pool (simultaneous pull without Stream ID) |
| **12106–12150**| UDP | Dynamic Route Listeners | Inbound / Bidirectional | Dedicated 1:1 SRT listener ports |

---

## Firewall / Security Group Recommendations

### Ubuntu UFW Setup
```bash
# Allow web dashboard & API
sudo ufw allow 8080/tcp

# Allow SRT MediaMTX core
sudo ufw allow 8890/udp

# Allow SLS Multi-Client Hub & Dedicated Route ports
sudo ufw allow 12105:12150/udp

# Allow WebRTC & HLS preview (if accessed directly)
sudo ufw allow 8888/tcp
sudo ufw allow 8889/tcp
sudo ufw allow 8889/udp

# Enable UFW
sudo ufw enable
```

### Latency Buffer Calculation
To ensure packet recovery over lossy public networks:
$$\text{Recommended Latency} = \max(200\text{ ms}, 4 \times \text{RTT})$$

| Network Environment | Ping RTT | Packet Loss | Recommended SRT Latency |
|:---|:---|:---|:---|
| Local LAN / Fiber Intranet | < 5 ms | 0% | 120 – 200 ms |
| Domestic WAN / Broadband | 20 – 50 ms | 0.5% – 2% | 500 – 1000 ms |
| Mobile 4G/5G Cellular Bonding | 50 – 120 ms | 2% – 8% | 1500 – 2500 ms |
| Transcontinental / Satellite | 150 – 300 ms | 5% – 15% | 3000 – 5000 ms |
