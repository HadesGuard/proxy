#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/3proxy/conf/3proxy.cfg"
FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

if [[ ! -f "$CFG" ]]; then
  echo "Config not found: $CFG" >&2
  exit 1
fi

# Quick guard: avoid double-inject unless --force
if grep -qE 'auth\.guild\.xyz' "$CFG" && [[ $FORCE -eq 0 ]]; then
  echo "Found existing rules for guild.xyz in $CFG."
  echo "If you really want to inject again, run: sudo $0 --force"
  exit 0
fi

echo "=== Upstream proxy settings (for guild.xyz) ==="
read -rp "Type (http/socks5) [http]: " PT
PT=${PT:-http}
PT_LOWER=$(echo "$PT" | tr 'A-Z' 'a-z')
if [[ "$PT_LOWER" != "http" && "$PT_LOWER" != "socks5" ]]; then
  echo "Invalid type. Use http or socks5." >&2
  exit 1
fi

read -rp "Upstream host (e.g. 203.0.113.7): " UP_HOST
read -rp "Upstream port (e.g. 8080): " UP_PORT
if [[ -z "${UP_HOST}" || -z "${UP_PORT}" ]]; then
  echo "Host/port must not be empty." >&2
  exit 1
fi

read -rp "Use auth? (y/N): " USE_AUTH
USE_AUTH=${USE_AUTH:-N}
UP_USER=""
UP_PASS=""
if [[ "$USE_AUTH" =~ ^[Yy]$ ]]; then
  read -rp "Upstream username: " UP_USER
  read -rsp "Upstream password: " UP_PASS
  echo
fi

# Compose parent line for 3proxy
if [[ -n "$UP_USER" || -n "$UP_PASS" ]]; then
  PARENT_LINE="parent 1000 ${PT_LOWER} ${UP_HOST} ${UP_PORT} ${UP_USER} ${UP_PASS}"
else
  PARENT_LINE="parent 1000 ${PT_LOWER} ${UP_HOST} ${UP_PORT}"
fi

TS=$(date +%Y%m%d-%H%M%S)
BACKUP="${CFG}.bak-${TS}"
cp -a "$CFG" "$BACKUP"
echo "Backup created at: $BACKUP"

TMP="$(mktemp)"
# We’ll inject per-service (before each proxy -p... that immediately follows `allow <user>`)

awk -v parent_line="$PARENT_LINE" '
function print_block(u){
  print "allow " u " * auth.guild.xyz,*.guild.xyz"
  print parent_line
  print "allow " u
}
BEGIN{
  pending_user="";
  injected_any=0;
}
{
  line=$0;

  # detect existing rules to avoid duplicate when --force not used (we keep but won’t duplicate block)
  if (line ~ /auth\.guild\.xyz/) { /* just carry on */ }

  # If previous line was "allow <user>", remember it and delay emission
  if (pending_user == "" && match(line, /^[[:space:]]*allow[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*$/, m)) {
    pending_user = m[1];
    stored_allow = line;   # store original allow line in case not followed by proxy
    next;
  }

  # If we were waiting for a proxy line and current line is proxy -p..., inject the block
  if (pending_user != "" && line ~ /^[[:space:]]*proxy[[:space:]]+-p[0-9]+/) {
    # Inject the guild route block for that user
    print_block(pending_user);
    print line; # keep original proxy line
    pending_user="";
    injected_any=1;
    next;
  }

  # If pending_user but current line is NOT proxy, flush stored allow and continue
  if (pending_user != "") {
    print stored_allow;
    pending_user="";
    # fall-through to print current line too
  }

  print line;
}
END{
  if (pending_user != "") {
    # file ended right after an allow line without a proxy line; just print it
    print stored_allow;
  }
}
' "$BACKUP" > "$TMP"

mv "$TMP" "$CFG"

echo "Injected routing block for *.guild.xyz (type=${PT_LOWER}, host=${UP_HOST}, port=${UP_PORT})."
echo "Restarting 3proxy..."
if systemctl is-enabled --quiet 3proxy 2>/dev/null; then
  systemctl restart 3proxy
  systemctl --no-pager --full status 3proxy | sed -n "1,15p"
else
  echo "Note: 3proxy is not a systemd service here; restart it manually if needed."
fi

echo
echo "=== Quick tests (replace USER/PASS/IP/PORT accordingly) ==="
echo "curl -Iv --max-time 15 -x http://user1:PASS@YOUR_VPS_IP:32585 https://auth.guild.xyz/v1/health/live"
echo "curl -Iv --max-time 15 -x http://user1:PASS@YOUR_VPS_IP:32585 https://example.com"
