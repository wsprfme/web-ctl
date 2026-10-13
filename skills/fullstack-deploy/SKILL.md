---
name: fullstack-deploy
description: Deploy web apps behind Cloudflare Tunnel with web-ctl (nginx + DNS).
---

# Fullstack Deploy (Cloudflare Tunnel)

Deploy, list, or remove fullstack web apps on this VM. Public traffic goes
through a Cloudflare Tunnel on a base domain — never direct inbound ports
(typical setup: firewall/Security Group blocks all inbound, tunnel is
outbound-only).

## Arsitektur (pakai yang ada, jangan dibangun ulang)

```
Internet → Cloudflare (SSL) → cloudflared tunnel (systemd: cloudflared)
                                │
                                ▼
                   nginx :80 (sites-enabled/<app>, routed by hostname)
                                │
                                ▼
                   backend app (systemd webapp-<app> / custom service)
```

- Domain basis: `jolink.co.id` → tiap app = `<app>.jolink.co.id` (example.com → `<app>.example.com` on generic installs)
- Config tunnel: `~/.cloudflared/config.yml` (ingress hostname → localhost:port)
- Registry semua app: `/opt/webapps/registry.json`
- Tool utama: `web-ctl` (`/usr/local/bin/web-ctl`)
- App bawaan: `status.jolink.co.id` (svc `status-api`, port 8081) — JANGAN pakai port 8081 untuk app lain

## Port yang sudah dipakai (JANGAN pakai ulang)

Cek `web-ctl list` untuk port terpakai saat ini. Port yang umumnya reserved:

| Port | Kegunaan |
|---|---|
| 80 | nginx (front, reserved) |
| 8081 | status-api dashboard |
| 3306 / 6379 | database / cache (internal) |

## Deploy app baru

1. Taruh file di `/opt/webapps/<app>/`, backend listen `127.0.0.1:<port>`
   (bukan port yang sudah dipakai/reserved)
2. Bikin service systemd:
   ```bash
   web-ctl unit <app> "<exec-start>" --port <port>
   sudo systemctl enable --now webapp-<app>
   ```
   Service yang dikelola sistem lain: `web-ctl register <app> <port> <service>`
3. Daftarkan: `web-ctl add <app> <port>`
   (otomatis: nginx site + ingress tunnel + DNS CNAME + reload)
4. Verifikasi: `curl -s -o /dev/null -w '%{http_code}' https://<app>.<domain>/`
   — kalau NXDOMAIN/000, tunggu ~30 detik (DNS propagation)

## Operasional

- `web-ctl list` — status semua app (running/stopped + URL)
- `web-ctl logs <app> -n 100` — journalctl app
- `web-ctl restart <app>`
- `web-ctl remove <app>` (file tetap ada, config dihapus)
- Tunnel mati: `sudo systemctl restart cloudflared`
- Setelah edit `~/.cloudflared/config.yml` manual: WAJIB `sudo systemctl restart cloudflared`
- Cek DNS manual: `cloudflared tunnel route dns <tunnel> <sub>.<domain>`
- Nginx error: `sudo nginx -t` sebelum reload

## Aturan

- **Jangan** buka port inbound di firewall/Security Group — percuma (diblokir
  upstream) dan tidak perlu; semua traffic publik lewat tunnel
- Semua service **harus** systemd-enabled (auto-start setelah reboot)
- Jangan hapus app bawaan dari registry (mis. `status` dashboard)
- Frontend SPA: build ke `<app>/public`, serve via nginx `root`; API via `location /api/`
- Passwordless sudo untuk agent user diperlukan (web-ctl nulis file via `sudo -n tee`)
