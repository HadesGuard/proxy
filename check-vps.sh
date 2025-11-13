#!/usr/bin/env bash

set -euo pipefail

PROXY_PORTS=("3128" "8080" "8000" "1080")

print_header() {
  echo
  echo "========================================"
  echo "  $1"
  echo "========================================"
}

print_ok() {
  echo -e "✅ $1"
}

print_warn() {
  echo -e "⚠️  $1"
}

print_err() {
  echo -e "❌ $1"
}

# Detect OS for ping compatibility
detect_ping_timeout() {
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "-W 2000"  # macOS: -W timeout in milliseconds
  else
    echo "-w 2"     # Linux: -w deadline in seconds
  fi
}

PING_TIMEOUT=$(detect_ping_timeout)

# 1. IP & Network
print_header "1. KIỂM TRA IP & NETWORK"

# Get public IP with timeout
PUB_IP="unknown"
if command -v curl >/dev/null 2>&1; then
  PUB_IP=$(curl -s --max-time 5 --connect-timeout 3 ipinfo.io/ip 2>/dev/null || \
           curl -s --max-time 5 --connect-timeout 3 ifconfig.me 2>/dev/null || \
           echo "unknown")
fi

# Get interface IP - try common interface names first
IF_IP=""
for iface in eth0 ens3 ens5 enp0s3 enp0s8; do
  IF_IP=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 || true)
  if [[ -n "$IF_IP" ]]; then
    break
  fi
done

# Fallback: get first non-loopback IP
if [[ -z "$IF_IP" ]]; then
  IF_IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127/ {print $2}' | head -n1 | cut -d/ -f1 || echo "")
fi

if [[ -z "$IF_IP" ]]; then
  IF_IP="unknown"
fi

echo "IP trong VPS  : $IF_IP"
echo "IP public     : $PUB_IP"

if [[ "$IF_IP" != "unknown" && "$PUB_IP" != "unknown" && "$IF_IP" == "$PUB_IP" ]]; then
  print_ok "VPS KHÔNG bị NAT (IP trong máy trùng IP public)."
elif [[ "$IF_IP" != "unknown" && "$PUB_IP" != "unknown" ]]; then
  print_warn "Có vẻ VPS đang sau NAT (IP trong máy khác IP public). Làm proxy có thể gặp vấn đề."
else
  print_warn "Không thể xác định đầy đủ thông tin IP."
fi

# Ping test
echo
echo "Ping 8.8.8.8..."
if ping -c 3 ${PING_TIMEOUT} 8.8.8.8 >/dev/null 2>&1; then
  print_ok "Ping 8.8.8.8 OK (network outbound ổn)."
else
  print_warn "Ping 8.8.8.8 FAIL (ICMP có thể bị chặn bởi firewall/provider - không sao nếu HTTP/HTTPS vẫn hoạt động)."
  # Alternative connectivity test using TCP
  echo "  → Kiểm tra kết nối TCP thay thế..."
  if command -v timeout >/dev/null 2>&1; then
    if timeout 2 bash -c 'cat < /dev/null > /dev/tcp/8.8.8.8/53' 2>/dev/null; then
      print_ok "  Kết nối TCP đến 8.8.8.8:53 OK (network outbound hoạt động)."
    else
      print_err "  Kết nối TCP cũng FAIL - có vấn đề với outbound network."
    fi
  elif command -v nc >/dev/null 2>&1; then
    if nc -z -w 2 8.8.8.8 53 2>/dev/null; then
      print_ok "  Kết nối TCP đến 8.8.8.8:53 OK (network outbound hoạt động)."
    else
      print_err "  Kết nối TCP cũng FAIL - có vấn đề với outbound network."
    fi
  fi
fi

echo "Ping google.com..."
if ping -c 3 ${PING_TIMEOUT} google.com >/dev/null 2>&1; then
  print_ok "Ping google.com OK (DNS + outbound ổn)."
else
  print_warn "Ping google.com FAIL (ICMP có thể bị chặn - kiểm tra DNS bằng cách khác)."
  # Test DNS resolution
  if command -v dig >/dev/null 2>&1; then
    if dig +short +timeout=2 google.com >/dev/null 2>&1; then
      print_ok "  DNS resolution OK (dig google.com thành công)."
    else
      print_warn "  DNS resolution FAIL - kiểm tra lại DNS settings."
    fi
  elif command -v nslookup >/dev/null 2>&1; then
    if nslookup -timeout=2 google.com >/dev/null 2>&1; then
      print_ok "  DNS resolution OK (nslookup google.com thành công)."
    else
      print_warn "  DNS resolution FAIL - kiểm tra lại DNS settings."
    fi
  fi
  # Test HTTP connectivity
  if command -v curl >/dev/null 2>&1; then
    if curl -s --max-time 3 --connect-timeout 2 https://www.google.com >/dev/null 2>&1; then
      print_ok "  HTTP/HTTPS connectivity OK (curl google.com thành công)."
    else
      print_warn "  HTTP/HTTPS connectivity có vấn đề."
    fi
  fi
fi

# 2. Ports & Firewall
print_header "2. KIỂM TRA PORT & FIREWALL"

echo "Kiểm tra port proxy có đang bị chiếm không:"
for PORT in "${PROXY_PORTS[@]}"; do
  # Try ss first, fallback to netstat if ss not available or requires root
  if command -v ss >/dev/null 2>&1; then
    if ss -ltnp 2>/dev/null | grep -q ":$PORT "; then
      print_warn "Port $PORT đang được sử dụng:"
      ss -ltnp 2>/dev/null | grep ":$PORT " || true
    else
      print_ok "Port $PORT đang rảnh."
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tlnp 2>/dev/null | grep -q ":$PORT "; then
      print_warn "Port $PORT đang được sử dụng:"
      netstat -tlnp 2>/dev/null | grep ":$PORT " || true
    else
      print_ok "Port $PORT đang rảnh."
    fi
  else
    print_warn "Không tìm thấy ss hoặc netstat để kiểm tra port."
    break
  fi
done

echo
if command -v ufw >/dev/null 2>&1; then
  echo "Trạng thái UFW:"
  ufw status || true
else
  print_warn "UFW không cài hoặc không dùng (không sao nếu em dùng iptables trực tiếp)."
fi

echo
echo "Một số rule iptables (nếu có):"
if command -v iptables >/dev/null 2>&1; then
  iptables -L -n | head -n 20 || true
else
  print_warn "iptables không có (trên một số hệ thống dùng nftables, không sao)."
fi

# 3. System Resources
print_header "3. TÀI NGUYÊN HỆ THỐNG"

# Get CPU cores
CPU_CORES=1
if command -v nproc >/dev/null 2>&1; then
  CPU_CORES=$(nproc)
elif command -v lscpu >/dev/null 2>&1; then
  CPU_CORES=$(lscpu | grep -E '^CPU\(s\):' | awk '{print $2}' || echo "1")
fi

echo "CPU info:"
if command -v lscpu >/dev/null 2>&1; then
  lscpu | grep -E 'Model name|CPU\(s\):' || true
else
  if command -v nproc >/dev/null 2>&1; then
    echo "CPU cores: $CPU_CORES"
    print_warn "lscpu không có, chỉ hiển thị số core."
  else
    print_warn "Không thể lấy thông tin CPU."
  fi
fi

echo
echo "RAM:"
RAM_INFO=$(free -m 2>/dev/null || echo "")
if [[ -n "$RAM_INFO" ]]; then
  free -h || true
  # Extract available RAM in MB - try column 7 (available) first, fallback to free (column 4)
  AVAIL_RAM_MB=$(echo "$RAM_INFO" | awk '/^Mem:/ {
    if (NF >= 7 && $7 != "") print $7; 
    else if (NF >= 4) print $4;
    else print "0"
  }' || echo "0")
  # If we got a value, ensure it's numeric
  if ! [[ "$AVAIL_RAM_MB" =~ ^[0-9]+$ ]]; then
    AVAIL_RAM_MB=0
  fi
else
  AVAIL_RAM_MB=0
  print_warn "Không thể lấy thông tin RAM."
fi

echo
echo "Disk (/):"
df -h / || true

# 4. Limits & sysctl
print_header "4. LIMITS & SYSCTL"

echo "ulimit -n (số file/connection tối đa per process):"
ULIMIT_N=$(ulimit -n || echo "unknown")
echo "ulimit -n = $ULIMIT_N"

if [[ "$ULIMIT_N" =~ ^[0-9]+$ ]] && [[ "$ULIMIT_N" -lt 65535 ]]; then
  print_warn "ulimit -n hơi thấp, nên tăng lên >= 65535 nếu chạy nhiều user proxy."
else
  print_ok "ulimit -n ổn hoặc khá cao."
fi

echo
if command -v sysctl >/dev/null 2>&1; then
  echo "fs.file-max:"
  sysctl fs.file-max || true
else
  print_warn "sysctl không có (hiếm)."
fi

# 5. Uptime & load
print_header "5. UPTIME & LOAD"

uptime || true

# 6. Proxy Recommendation
print_header "6. ĐỀ XUẤT SỐ LƯỢNG PROXY"

# Calculate recommended proxy count
RECOMMENDED_PROXY=0
WARNINGS=()

# Base calculation: each proxy needs ~5-10MB RAM for light usage, ~20-50MB for heavy
# Conservative estimate: 20MB per proxy
if [[ "$AVAIL_RAM_MB" =~ ^[0-9]+$ ]] && [[ "$AVAIL_RAM_MB" -gt 0 ]]; then
  # Reserve 200MB for system, calculate based on available RAM
  RAM_FOR_PROXY=$((AVAIL_RAM_MB - 200))
  if [[ $RAM_FOR_PROXY -lt 0 ]]; then
    RAM_FOR_PROXY=0
  fi
  # 20MB per proxy (conservative)
  PROXY_BY_RAM=$((RAM_FOR_PROXY / 20))
else
  PROXY_BY_RAM=0
  WARNINGS+=("Không thể tính toán dựa trên RAM")
fi

# CPU-based: 1 core can handle many proxies (3proxy is lightweight)
# Conservative: 50-100 proxies per core
PROXY_BY_CPU=$((CPU_CORES * 50))

# ulimit-based: each proxy connection uses file descriptors
# If ulimit is low, limit the number
if [[ "$ULIMIT_N" =~ ^[0-9]+$ ]]; then
  # Each proxy might have 10-50 concurrent connections
  # Conservative: 20 connections per proxy
  if [[ "$ULIMIT_N" -lt 1024 ]]; then
    PROXY_BY_ULIMIT=10
    WARNINGS+=("ulimit thấp sẽ giới hạn số lượng proxy")
  elif [[ "$ULIMIT_N" -lt 65535 ]]; then
    PROXY_BY_ULIMIT=$((ULIMIT_N / 20))
    WARNINGS+=("Nên tăng ulimit để hỗ trợ nhiều proxy hơn")
  else
    PROXY_BY_ULIMIT=1000  # High enough, not a limiting factor
  fi
else
  PROXY_BY_ULIMIT=50
  WARNINGS+=("Không thể xác định ulimit")
fi

# Take the minimum of all factors (most restrictive)
if [[ $PROXY_BY_RAM -gt 0 ]] && [[ $PROXY_BY_CPU -gt 0 ]] && [[ $PROXY_BY_ULIMIT -gt 0 ]]; then
  RECOMMENDED_PROXY=$PROXY_BY_RAM
  if [[ $PROXY_BY_CPU -lt $RECOMMENDED_PROXY ]]; then
    RECOMMENDED_PROXY=$PROXY_BY_CPU
  fi
  if [[ $PROXY_BY_ULIMIT -lt $RECOMMENDED_PROXY ]]; then
    RECOMMENDED_PROXY=$PROXY_BY_ULIMIT
  fi
elif [[ $PROXY_BY_RAM -gt 0 ]]; then
  RECOMMENDED_PROXY=$PROXY_BY_RAM
elif [[ $PROXY_BY_CPU -gt 0 ]]; then
  RECOMMENDED_PROXY=$PROXY_BY_CPU
else
  RECOMMENDED_PROXY=10  # Safe default
fi

# Ensure minimum and maximum bounds
if [[ $RECOMMENDED_PROXY -lt 5 ]]; then
  RECOMMENDED_PROXY=5
  WARNINGS+=("Tài nguyên hạn chế, chỉ nên tạo số lượng proxy tối thiểu")
elif [[ $RECOMMENDED_PROXY -gt 500 ]]; then
  RECOMMENDED_PROXY=500
  WARNINGS+=("Giới hạn tối đa 500 proxy để đảm bảo ổn định")
fi

echo "Phân tích tài nguyên:"
echo "  - CPU cores: $CPU_CORES"
if [[ "$AVAIL_RAM_MB" =~ ^[0-9]+$ ]] && [[ "$AVAIL_RAM_MB" -gt 0 ]]; then
  echo "  - RAM available: ${AVAIL_RAM_MB}MB"
  echo "  - Tính theo RAM: ~$PROXY_BY_RAM proxy (20MB/proxy, dự trữ 200MB cho hệ thống)"
fi
echo "  - Tính theo CPU: ~$PROXY_BY_CPU proxy (50 proxy/core)"
if [[ "$ULIMIT_N" =~ ^[0-9]+$ ]]; then
  echo "  - Tính theo ulimit: ~$PROXY_BY_ULIMIT proxy (20 connections/proxy)"
fi

echo
echo "📊 ĐỀ XUẤT: Tạo $RECOMMENDED_PROXY proxy"
echo

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "Lưu ý:"
  for warning in "${WARNINGS[@]}"; do
    print_warn "  - $warning"
  done
  echo
fi

echo "Gợi ý sử dụng:"
echo "  ./setup-proxy.sh"
echo "  (Khi được hỏi, nhập: $RECOMMENDED_PROXY)"
echo

# Calculate resource usage estimate
EST_RAM=$((RECOMMENDED_PROXY * 20))
EST_CONNECTIONS=$((RECOMMENDED_PROXY * 20))
echo "Ước tính sử dụng tài nguyên với $RECOMMENDED_PROXY proxy:"
echo "  - RAM: ~${EST_RAM}MB (nếu tất cả proxy hoạt động đồng thời)"
echo "  - File descriptors: ~${EST_CONNECTIONS} (nếu mỗi proxy có 20 connections)"
if [[ "$ULIMIT_N" =~ ^[0-9]+$ ]] && [[ $EST_CONNECTIONS -gt $ULIMIT_N ]]; then
  print_warn "  ⚠️  Cần tăng ulimit lên ít nhất $((EST_CONNECTIONS + 1000)) để đảm bảo ổn định"
fi

echo
print_ok "Hoàn thành kiểm tra cơ bản VPS cho proxy."
echo "Nếu phần nào báo ⚠️ hoặc ❌ thì xem lại trước khi triển khai proxy."
