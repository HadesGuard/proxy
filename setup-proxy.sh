#!/usr/bin/env bash
set -euo pipefail

echo "==============================================="
echo " 3PROXY AUTO SETUP - RANDOM NAT-LIKE PORTS"
echo "==============================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Script này cần chạy với quyền root (sudo)."
  exit 1
fi

# Hỏi số lượng proxy
read -p "[+] Nhập số lượng proxy muốn tạo: " COUNT

# Validate input
if [ -z "$COUNT" ]; then
  echo "[-] Số lượng proxy không được để trống."
  exit 1
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -le 0 ]; then
  echo "[-] Số lượng proxy không hợp lệ."
  exit 1
fi

echo "[+] Sẽ tạo $COUNT proxy (user1..user$COUNT) với port RANDOM."

# Lấy IP server (có thể override bằng export SERVER_IP=...)
if [ -z "${SERVER_IP:-}" ]; then
  echo "[+] Đang tự động lấy IP server..."
  
  # Thử nhiều cách lấy IP
  # Method 1: hostname -I
  SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
  
  # Method 2: ip command
  if [ -z "${SERVER_IP:-}" ]; then
    for iface in eth0 ens3 ens5 enp0s3 enp0s8; do
      SERVER_IP=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 || echo "")
      if [ -n "${SERVER_IP:-}" ]; then
        break
      fi
    done
  fi
  
  # Method 3: ip addr show (fallback)
  if [ -z "${SERVER_IP:-}" ]; then
    SERVER_IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127/ {print $2}' | head -n1 | cut -d/ -f1 || echo "")
  fi
  
  # Method 4: ifconfig (nếu có)
  if [ -z "${SERVER_IP:-}" ] && command -v ifconfig >/dev/null 2>&1; then
    SERVER_IP=$(ifconfig 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | head -n1 | awk '{print $2}' || echo "")
  fi
fi

# Nếu vẫn không lấy được, hỏi user
if [ -z "${SERVER_IP:-}" ]; then
  echo "[-] Không thể tự động lấy IP server."
  read -p "[+] Vui lòng nhập IP server của bạn: " SERVER_IP
  
  # Validate input
  if [ -z "${SERVER_IP:-}" ]; then
    echo "[-] IP không được để trống."
    exit 1
  fi
  
  # Basic IP validation (simple check)
  if ! [[ "${SERVER_IP:-}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "[-] IP không hợp lệ. Format: x.x.x.x"
    exit 1
  fi
fi

echo "[+] SERVER_IP = $SERVER_IP"

echo "[+] apt update + cài build-essential git openssl..."
apt update -y
apt install -y git build-essential openssl

# Cài 3proxy nếu chưa có
if ! command -v 3proxy >/dev/null 2>&1; then
  echo "[+] Chưa thấy 3proxy, tiến hành clone & build..."
  TMPDIR=$(mktemp -d)
  # Ensure cleanup on exit
  trap "rm -rf '$TMPDIR'" EXIT INT TERM
  cd "$TMPDIR"
  if ! git clone https://github.com/z3APA3A/3proxy.git; then
    echo "[-] Lỗi khi clone 3proxy repository."
    exit 1
  fi
  cd 3proxy
  if ! make -f Makefile.Linux; then
    echo "[-] Lỗi khi build 3proxy."
    exit 1
  fi
  if [ ! -f bin/3proxy ]; then
    echo "[-] Không tìm thấy file binary sau khi build."
    exit 1
  fi
  install bin/3proxy /usr/local/bin/3proxy
  cd /
  rm -rf "$TMPDIR"
  trap - EXIT INT TERM
else
  echo "[+] Đã có 3proxy, bỏ qua bước build."
fi

# Thư mục config & log
CONF_DIR="/etc/3proxy/conf"
LOG_DIR="/etc/3proxy/logs"
BIN_PATH="/usr/local/bin/3proxy"
CONF_FILE="$CONF_DIR/3proxy.cfg"
PROXY_LIST="/root/proxies.txt"
SYSTEMD_SERVICE="/etc/systemd/system/3proxy.service"

mkdir -p "$CONF_DIR" "$LOG_DIR"

# Sinh user/pass + port RANDOM, không trùng
declare -a USERS PASSWORDS PORTS

PORT_MIN=20000
PORT_MAX=60000

# Check if port is available
is_port_available() {
  local port=$1
  # Check if port is in use
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | grep -q ":$port "; then
      return 1
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tln 2>/dev/null | grep -q ":$port "; then
      return 1
    fi
  fi
  return 0
}

gen_port() {
  local max_attempts=1000
  local attempts=0
  
  while [ $attempts -lt $max_attempts ]; do
    local p=$((RANDOM % (PORT_MAX - PORT_MIN + 1) + PORT_MIN))
    # Check trùng trong array
    local used=0
    for ex in "${PORTS[@]}"; do
      if [ "$ex" = "$p" ]; then
        used=1
        break
      fi
    done
    
    # Check if port is actually available on system
    if [ $used -eq 0 ] && is_port_available "$p"; then
      echo "$p"
      return 0
    fi
    
    attempts=$((attempts + 1))
  done
  
  echo "[-] Không thể tìm port trống sau $max_attempts lần thử." >&2
  return 1
}

echo "[+] Đang sinh user/pass + port random..."

for ((i=1; i<=COUNT; i++)); do
  U="user$i"
  # Generate stronger password (16 hex chars = 64 bits)
  P="$(openssl rand -hex 8)"
  PORT="$(gen_port)"
  
  if [ $? -ne 0 ]; then
    echo "[-] Lỗi khi tạo port cho user $U."
    exit 1
  fi

  USERS+=("$U")
  PASSWORDS+=("$P")
  PORTS+=("$PORT")
done

# Tạo dòng users cho 3proxy.cfg
USERS_LINE="users"
for ((i=0; i<COUNT; i++)); do
  USERS_LINE+=" ${USERS[$i]}:CL:${PASSWORDS[$i]}"
done

# Ghi file cấu hình 3proxy
cat > "$CONF_FILE" <<EOF
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60

log $LOG_DIR/3proxy.log
logformat "L%t %E %U %C:%c %R:%r %O %I %h"

$USERS_LINE

# Chỉ cho phép client auth bằng user/pass
auth strong

# Lắng nghe từng proxy cho từng user
EOF

for ((i=0; i<COUNT; i++)); do
  U="${USERS[$i]}"
  PORT="${PORTS[$i]}"
  cat >> "$CONF_FILE" <<EOF
allow $U
proxy -p$PORT -n -a
EOF
done

# Tạo systemd service
cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=3proxy Proxy Server (Dynamic Multi-User)
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH $CONF_FILE
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Configure Firewall
echo
echo "[+] Cấu hình Firewall..."

# Detect SSH port (critical - don't lock yourself out!)
if command -v ss >/dev/null 2>&1; then
  SSH_PORT=$(ss -tlnp 2>/dev/null | grep -E 'sshd|:22 ' | head -n1 | awk '{print $4}' | cut -d: -f2 || echo "22")
elif command -v netstat >/dev/null 2>&1; then
  SSH_PORT=$(netstat -tlnp 2>/dev/null | grep -E 'sshd|:22 ' | head -n1 | awk '{print $4}' | cut -d: -f2 || echo "22")
else
  SSH_PORT="22"
fi

# Try UFW first (preferred)
if ! command -v ufw >/dev/null 2>&1; then
  echo "[+] UFW chưa cài, đang cài đặt..."
  apt install -y ufw
fi

if command -v ufw >/dev/null 2>&1; then
  echo "[+] Sử dụng UFW để cấu hình firewall..."
  
  # Check UFW status
  UFW_STATUS=$(ufw status 2>/dev/null | head -n1 || echo "inactive")
  if echo "$UFW_STATUS" | grep -q "inactive\|Status: inactive"; then
    echo "[+] UFW đang tắt, sẽ bật và cấu hình..."
    
    # Allow SSH first (critical!)
    echo "[+] Cho phép SSH port $SSH_PORT (để không bị khóa khỏi server)..."
    ufw allow "$SSH_PORT/tcp" >/dev/null 2>&1 || true
    
    # Allow all proxy ports
    echo "[+] Mở $COUNT port proxy trong firewall..."
    for PORT in "${PORTS[@]}"; do
      ufw allow "$PORT/tcp" >/dev/null 2>&1 || true
      echo "  ✓ Đã mở port $PORT"
    done
    
    # Enable UFW with default deny
    echo "[+] Kích hoạt UFW (default deny, chỉ cho phép SSH và proxy ports)..."
    ufw --force enable >/dev/null 2>&1 || true
    
    echo "[+] UFW đã được cấu hình và kích hoạt."
  else
    echo "[+] UFW đã được kích hoạt, chỉ thêm rules cho proxy ports..."
    
    # Ensure SSH is allowed
    if ! ufw status | grep -q "$SSH_PORT/tcp"; then
      echo "[+] Cho phép SSH port $SSH_PORT..."
      ufw allow "$SSH_PORT/tcp" >/dev/null 2>&1 || true
    fi
    
    # Allow all proxy ports
    echo "[+] Mở $COUNT port proxy trong firewall..."
    for PORT in "${PORTS[@]}"; do
      # Check if rule already exists
      if ! ufw status | grep -q "$PORT/tcp"; then
        ufw allow "$PORT/tcp" >/dev/null 2>&1 || true
        echo "  ✓ Đã mở port $PORT"
      else
        echo "  → Port $PORT đã được mở trước đó"
      fi
    done
  fi
  
  # Show UFW status summary
  echo
  echo "[+] Trạng thái Firewall (UFW):"
  ufw status numbered | head -n 20 || true
  
elif command -v iptables >/dev/null 2>&1; then
  echo "[+] UFW không có, sử dụng iptables..."
  echo "[!] CẢNH BÁO: Script sẽ thêm rules iptables nhưng KHÔNG tự động cấu hình đầy đủ."
  echo "[!] Bạn cần tự cấu hình iptables hoặc cài UFW để quản lý firewall dễ hơn."
  echo
  echo "[+] Để mở ports proxy bằng iptables, chạy các lệnh sau:"
  echo "    # Cho phép SSH"
  echo "    iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT"
  echo "    # Cho phép proxy ports"
  for PORT in "${PORTS[@]}"; do
    echo "    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT"
  done
  echo "    # Lưu rules (tùy hệ thống)"
  echo "    # Debian/Ubuntu: iptables-save > /etc/iptables/rules.v4"
  echo "    # CentOS/RHEL: service iptables save"
  
else
  echo "[!] CẢNH BÁO: Không tìm thấy UFW hoặc iptables."
  echo "[!] Bạn cần tự cấu hình firewall để mở các port proxy:"
  for PORT in "${PORTS[@]}"; do
    echo "    - Port $PORT"
  done
  echo "[!] Và đảm bảo SSH port $SSH_PORT được mở."
fi

# Reload & enable service
systemctl daemon-reload
systemctl enable 3proxy.service

# Stop service if running (in case of re-run)
if systemctl is-active --quiet 3proxy.service 2>/dev/null; then
  systemctl stop 3proxy.service
fi

# Ghi danh sách proxy cho client (tạo TRƯỚC khi start service để đảm bảo luôn có file)
echo
echo "[+] Đang export danh sách proxy..."
echo "[+] Tạo file proxy list với $COUNT proxy..."

# Format 1: user:pass@ip:port (cho curl, wget, etc)
PROXY_LIST="/root/proxies.txt"
echo "[+] Ghi danh sách proxy ra $PROXY_LIST"
rm -f "$PROXY_LIST"
touch "$PROXY_LIST"
for ((i=0; i<COUNT; i++)); do
  echo "${USERS[$i]}:${PASSWORDS[$i]}@$SERVER_IP:${PORTS[$i]}" >> "$PROXY_LIST"
done

# Format 2: http://user:pass@ip:port (cho browser, tools)
PROXY_LIST_HTTP="/root/proxies_http.txt"
rm -f "$PROXY_LIST_HTTP"
touch "$PROXY_LIST_HTTP"
for ((i=0; i<COUNT; i++)); do
  echo "http://${USERS[$i]}:${PASSWORDS[$i]}@$SERVER_IP:${PORTS[$i]}" >> "$PROXY_LIST_HTTP"
done

# Format 3: ip:port:user:pass (cho một số tools)
PROXY_LIST_IPPORT="/root/proxies_ipport.txt"
rm -f "$PROXY_LIST_IPPORT"
touch "$PROXY_LIST_IPPORT"
for ((i=0; i<COUNT; i++)); do
  echo "$SERVER_IP:${PORTS[$i]}:${USERS[$i]}:${PASSWORDS[$i]}" >> "$PROXY_LIST_IPPORT"
done

# Set secure permissions (readable only by root)
chmod 600 "$PROXY_LIST" "$PROXY_LIST_HTTP" "$PROXY_LIST_IPPORT" 2>/dev/null || true
chown root:root "$PROXY_LIST" "$PROXY_LIST_HTTP" "$PROXY_LIST_IPPORT" 2>/dev/null || true

# Verify files were created
if [ -f "$PROXY_LIST" ] && [ -s "$PROXY_LIST" ]; then
  echo "[+] ✓ Đã tạo $PROXY_LIST ($(wc -l < "$PROXY_LIST") dòng)"
else
  echo "[-] LỖI: Không tạo được $PROXY_LIST"
fi

if [ -f "$PROXY_LIST_HTTP" ] && [ -s "$PROXY_LIST_HTTP" ]; then
  echo "[+] ✓ Đã tạo $PROXY_LIST_HTTP ($(wc -l < "$PROXY_LIST_HTTP") dòng)"
else
  echo "[-] LỖI: Không tạo được $PROXY_LIST_HTTP"
fi

if [ -f "$PROXY_LIST_IPPORT" ] && [ -s "$PROXY_LIST_IPPORT" ]; then
  echo "[+] ✓ Đã tạo $PROXY_LIST_IPPORT ($(wc -l < "$PROXY_LIST_IPPORT") dòng)"
else
  echo "[-] LỖI: Không tạo được $PROXY_LIST_IPPORT"
fi

echo "[+] Đã tạo 3 file danh sách proxy:"
echo "  → $PROXY_LIST (format: user:pass@ip:port)"
echo "  → $PROXY_LIST_HTTP (format: http://user:pass@ip:port)"
echo "  → $PROXY_LIST_IPPORT (format: ip:port:user:pass)"

# Start service AFTER creating proxy list files
echo
echo "[+] Khởi động service 3proxy..."
systemctl start 3proxy.service

# Wait a moment and check service status
sleep 2
if systemctl is-active --quiet 3proxy.service; then
  echo "[+] Service 3proxy đã khởi động thành công."
else
  echo "[-] CẢNH BÁO: Service 3proxy không khởi động được. Kiểm tra:"
  echo "    systemctl status 3proxy"
  echo "    journalctl -u 3proxy -n 50"
  echo "[!] Lưu ý: File proxy list đã được tạo, bạn có thể kiểm tra và sửa service sau."
fi

echo
echo "==============================================="
echo " ✅ ĐÃ CÀI XONG 3proxy + TẠO $COUNT PROXY (PORT RANDOM)"
echo "==============================================="
echo
echo "📁 Files:"
echo "  → Config:     $CONF_FILE"
echo "  → Logs:       $LOG_DIR"
echo "  → Service:    systemctl status 3proxy"
echo
echo "📋 Danh sách proxy (3 formats):"
echo "  → $PROXY_LIST (user:pass@ip:port)"
echo "  → $PROXY_LIST_HTTP (http://user:pass@ip:port)"
echo "  → $PROXY_LIST_IPPORT (ip:port:user:pass)"
echo
echo "🧪 Test proxy:"
first_proxy=$(head -n 1 "$PROXY_LIST")
echo "  curl -x http://$first_proxy https://api.ipify.org"
echo
echo "📖 Xem danh sách:"
echo "  cat $PROXY_LIST"
echo "  cat $PROXY_LIST_HTTP"
echo "  cat $PROXY_LIST_IPPORT"
echo
echo "==============================================="