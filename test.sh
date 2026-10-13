#!/usr/bin/env bash
set -uo pipefail
# Smoke tests that run WITHOUT touching nginx/cloudflared/systemd.
# Usage: ./test.sh
PASS=0; FAIL=0
t() {  # t <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/tmp/webctl-test.out 2>&1; then
    echo "ok - $desc"; PASS=$((PASS+1))
  else
    echo "FAIL - $desc"; sed 's/^/    /' /tmp/webctl-test.out; FAIL=$((FAIL+1))
  fi
}

cd "$(dirname "$0")"

# isolated sandbox: fake HOME (cloudflared config) + fake WEBCTL_ROOT (registry)
SB=/tmp/webctl-test.$$; mkdir -p "$SB/.cloudflared" "$SB/webapps"
cat > "$SB/.cloudflared/config.yml" <<'EOF'
tunnel: test-tunnel-id
credentials-file: /tmp/creds.json

ingress:
  - hostname: app1.example.com
    service: http://localhost:3000
  - service: http_status:404
EOF
echo '{"apps": {}}' > "$SB/webapps/registry.json"
export HOME="$SB" WEBCTL_ROOT="$SB/webapps"

# 1. python syntax
t "python compiles" python3 -m py_compile web-ctl

# 2. no args prints usage
t "no args prints usage" bash -c './web-ctl | grep -q "web-ctl"'

# 3. config inference (domain + tunnel) via direct module load
t "infers domain + tunnel from config" python3 - <<'EOF'
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("webctl", "web-ctl").load_module()
assert m.get_domain() == "example.com", m.get_domain()
assert m.get_tunnel() == "test-tunnel-id", m.get_tunnel()
print("inference ok")
EOF

# 4. name validation rejects bad names
t "rejects invalid app name" bash -c \
  './web-ctl add "../evil" 3000 2>&1 | grep -q "alphanumeric"'

# 5. reserved port rejected
t "rejects port 80" bash -c \
  './web-ctl add foo 80 2>&1 | grep -qi "reserved"'

# 6. duplicate port rejected from registry
t "rejects duplicate port" bash -c '
  echo "{\"apps\": {\"x\": {\"port\": 3000, \"service\": \"x\", \"subdomain\": \"x\", \"url\": \"u\", \"path\": \"/tmp\"}}}" > "$WEBCTL_ROOT/registry.json"
  ./web-ctl add foo 3000 2>&1 | grep -q "already used"'

# 7. unit refuses empty exec
t "unit refuses empty exec" bash -c \
  './web-ctl unit foo 2>&1 | grep -q "usage"'

# 8. invalid port (not a number) rejected before any side effects
t "rejects non-numeric port" bash -c \
  './web-ctl add foo abc 2>&1 | grep -qi "invalid\|valueerror\|int()"'

# 9. missing subcommand arg prints usage
t "missing args print usage" bash -c \
  './web-ctl add onlyname 2>&1 | grep -q "web-ctl"'

echo
echo "passed: $PASS, failed: $FAIL"
rm -rf "$SB"
[ "$FAIL" -eq 0 ]
