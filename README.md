# web-ctl

Deploy fullstack web apps behind a **Cloudflare Tunnel** with one command.

Built for VMs where inbound ports are blocked (shared/NAT IPv4, cloud
security groups) — all public traffic enters through the outbound-only
`cloudflared` tunnel, and SSL terminates at Cloudflare for free.

```
web-ctl add myapp 3000
→ OK myapp -> https://myapp.example.com (127.0.0.1:3000, svc=webapp-myapp)
```

That single command does: nginx vhost → tunnel ingress entry → DNS CNAME →
registry update → reloads. No manual DNS, no certbot, no port openings.

```
Internet → Cloudflare (SSL) → cloudflared tunnel (outbound-only)
                                 ↓
                    nginx :80 (routed by hostname)
                                 ↓
                    app backend on 127.0.0.1:<port> (systemd)
```

## Install

Prerequisites: a Cloudflare Tunnel already created and running
(`cloudflared tunnel create` + systemd service), nginx installed, and the
user running the agent has passwordless sudo.

```bash
git clone https://github.com/wsprfme/web-ctl.git
cd web-ctl
sudo ./install.sh
```

The installer copies the binary to `/usr/local/bin/web-ctl`, creates
`/opt/webapps/registry.json`, grants scoped passwordless sudo, and drops the
`fullstack-deploy` skill into `~/.hermes/skills/` and
`~/.config/opencode/skill/` (for Hermes Agent / OpenCode users) so the agent
follows the right deploy workflow.

Domain and tunnel name are auto-inferred from `~/.cloudflared/config.yml`.
If inference fails, set them explicitly:

```bash
export WEBCTL_DOMAIN=example.com
export WEBCTL_TUNNEL=my-tunnel        # name or UUID
```

## Usage

```bash
# register an app whose systemd service already exists
web-ctl add myapp 3000

# register an app served by an externally-managed service
web-ctl register pterodactyl 80 php8.3-fpm

# generate a systemd unit for a new app, then start it
web-ctl unit myapp "node server.js" --port 3000
sudo systemctl enable --now webapp-myapp
web-ctl add myapp 3000

# day-2 operations
web-ctl list                 # status of every app
web-ctl logs myapp -n 100    # journalctl
web-ctl restart myapp
web-ctl remove myapp         # unregisters; files are kept

# route an extra subdomain to a port (nginx config up to you)
web-ctl route api 4000
```

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `WEBCTL_DOMAIN` | inferred from config.yml ingress hostnames | base domain (`<app>.<domain>`) |
| `WEBCTL_TUNNEL` | `tunnel:` key in config.yml | tunnel name/UUID for DNS routing |
| `WEBCTL_ROOT` | `/opt/webapps` | apps root + registry location |
| `WEBCTL_CF_CONFIG` | `~/.cloudflared/config.yml` | cloudflared config path |

Registry (`$WEBCTL_ROOT/registry.json`) tracks every app's port, service,
subdomain, and URL — the source of truth `web-ctl list` reads from.

## Design notes

- **Port 80 is reserved** (nginx front). Everything else on 127.0.0.1 is fair
  game; `web-ctl add` refuses ports already registered.
- **Files are never deleted**: `remove` drops only nginx config + registry
  entry, so a redeploy is just `add` again.
- **Tunnel-first design**: `add_cf_ingress` inserts the hostname *before* the
  catch-all `http_status:404` rule, then restarts cloudflared and routes DNS.
- **Passwordless sudo, narrowly scoped**: the installer grants only the exact
  commands web-ctl needs (nginx config write/test/reload, systemctl for
  webapp-* and cloudflared, cloudflared tunnel route dns).
- SPA pattern: build frontend to `<app>/public` served by nginx `root`, keep
  the API on the backend port behind `location /api/`.

## License

MIT
