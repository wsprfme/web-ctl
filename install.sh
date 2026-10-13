#!/usr/bin/env bash
# Install web-ctl + the fullstack-deploy skill for agent CLIs.
# Usage: sudo ./install.sh [domain]   (domain optional if config.yml already has ingress hostnames)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN=/usr/local/bin/web-ctl
WEBAPPS_ROOT=/opt/webapps

if [ "$(id -u)" -ne 0 ]; then
  echo "run with sudo: sudo ./install.sh" >&2
  exit 1
fi

# 1. binary
install -m 0755 "$REPO_DIR/web-ctl" "$BIN"
echo "installed $BIN"

# 2. apps root + registry
mkdir -p "$WEBAPPS_ROOT"
[ -f "$WEBAPPS_ROOT/registry.json" ] || echo '{"apps": {}}' > "$WEBAPPS_ROOT/registry.json"
echo "apps root: $WEBAPPS_ROOT"

# 3. passwordless sudo for the invoking (agent) user — web-ctl writes
#    /etc/nginx sites and restarts services via `sudo -n`
SUDOERS=/etc/sudoers.d/web-ctl
if [ ! -f "$SUDOERS" ]; then
  cat > "$SUDOERS" <<EOF
${SUDO_USER:-agentuser} ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/nginx/sites-available/*, /bin/rm -f /etc/nginx/sites-enabled/*, /bin/rm -f /etc/nginx/sites-available/*, /usr/sbin/nginx, /bin/systemctl reload nginx, /bin/systemctl restart nginx, /bin/systemctl restart cloudflared, /bin/systemctl stop webapp-*, /bin/systemctl restart webapp-*, /bin/tee /etc/systemd/system/webapp-*
EOF
  chmod 440 "$SUDOERS"
  echo "sudoers: $SUDOERS (passwordless for nginx/systemctl/cloudflared ops)"
fi

# 4. agent skills (hermes + opencode layout)
for skill_dir in \
  "$HOME/.hermes/skills" \
  "${HOME}/.config/opencode/skill"; do
  [ -d "$skill_dir" ] || continue
  mkdir -p "$skill_dir/fullstack-deploy"
  cp "$REPO_DIR/skills/fullstack-deploy/SKILL.md" "$skill_dir/fullstack-deploy/SKILL.md"
  echo "skill -> $skill_dir/fullstack-deploy/"
done

# 5. sanity check
"$BIN" list || true
echo
echo "done. prerequisites: cloudflared tunnel created + config.yml has ingress,"
echo "nginx installed. set WEBCTL_DOMAIN if it cannot be inferred."
