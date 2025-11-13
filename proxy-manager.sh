#!/usr/bin/env bash

set -euo pipefail

# Version & Commit Hash
VERSION="1.0.0"
COMMIT_HASH="af6203d"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_REPO="https://raw.githubusercontent.com/HadesGuard/proxy/main"
CHECK_SCRIPT="$SCRIPT_DIR/check-vps.sh"
SETUP_SCRIPT="$SCRIPT_DIR/setup-proxy.sh"
PROXY_LIST="/root/proxies.txt"
PROXY_LIST_HTTP="/root/proxies_http.txt"
PROXY_LIST_IPPORT="/root/proxies_ipport.txt"
SERVICE_NAME="3proxy"
TMP_SCRIPT_DIR="/tmp/proxy-scripts"

# Function to get commit hash from script
get_commit_hash() {
  local script_file="$1"
  if [ -f "$script_file" ]; then
    # Try to get COMMIT_HASH from script
    local hash=$(grep -m1 "^COMMIT_HASH=" "$script_file" 2>/dev/null | cut -d'"' -f2 || echo "")
    if [ -n "$hash" ]; then
      echo "$hash"
      return 0
    fi
  fi
  echo ""
  return 1
}

# Function to get latest commit hash from GitHub
get_latest_commit_hash() {
  local repo="HadesGuard/proxy"
  local branch="main"
  
  # Try GitHub API first
  local api_url="https://api.github.com/repos/$repo/commits/$branch"
  local hash=$(curl -sSL "$api_url" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | cut -c1-7 || echo "")
  
  if [ -n "$hash" ]; then
    echo "$hash"
    return 0
  fi
  
  # Fallback: try to get from raw file (if we store it in a separate file)
  # Or use file comparison as backup
  echo ""
  return 1
}

# Function to check and update manager script
check_update() {
  # Skip update check if running from local directory (development)
  if [ "$SCRIPT_DIR" != "/usr/local/bin" ] && [ "$SCRIPT_DIR" != "$HOME/.local/bin" ]; then
    return 0
  fi
  
  local current_script="$0"
  local latest_url="$GITHUB_REPO/proxy-manager.sh"
  local tmp_latest="/tmp/proxy-manager-latest.sh"
  
  # Get current commit hash
  local current_hash=$(get_commit_hash "$current_script")
  
  # Get latest commit hash from GitHub
  local latest_hash=$(get_latest_commit_hash)
  
  # If we have both hashes, compare them
  if [ -n "$current_hash" ] && [ -n "$latest_hash" ]; then
    if [ "$current_hash" != "$latest_hash" ]; then
      # Download latest version
      if ! curl -sSL "$latest_url" -o "$tmp_latest" 2>/dev/null; then
        return 1
      fi
      
      # Verify the downloaded file has the expected hash
      local downloaded_hash=$(get_commit_hash "$tmp_latest")
      if [ "$downloaded_hash" = "$latest_hash" ] || [ -z "$downloaded_hash" ]; then
        echo
        print_warning "Có phiên bản mới của proxy-manager!"
        echo "  Commit hiện tại: $current_hash"
        echo "  Commit mới:      $latest_hash"
        echo
        read -p "Bạn có muốn cập nhật? (y/N): " update_confirm
        
        if [[ "$update_confirm" =~ ^[Yy]$ ]]; then
          # Backup current version
          cp "$current_script" "${current_script}.bak" 2>/dev/null || true
          
          # Install new version
          if cp "$tmp_latest" "$current_script" 2>/dev/null; then
            chmod +x "$current_script"
            print_success "Đã cập nhật proxy-manager từ commit $current_hash lên $latest_hash!"
            echo
            read -p "Nhấn Enter để tiếp tục với phiên bản mới..."
            # Reload script
            exec "$current_script"
          else
            print_error "Không thể cập nhật. Cần quyền root hoặc quyền ghi."
            rm -f "$tmp_latest"
          fi
        else
          rm -f "$tmp_latest"
        fi
      else
        rm -f "$tmp_latest"
      fi
      return 0
    else
      # Same commit hash, no update needed
      return 0
    fi
  fi
  
  # Fallback: compare file content if hash comparison fails
  if ! curl -sSL "$latest_url" -o "$tmp_latest" 2>/dev/null; then
    return 1
  fi
  
  if [ -f "$current_script" ] && [ -f "$tmp_latest" ]; then
    if ! cmp -s "$current_script" "$tmp_latest"; then
      echo
      print_warning "Có phiên bản mới của proxy-manager!"
      echo "  (Phát hiện bằng so sánh file)"
      echo
      read -p "Bạn có muốn cập nhật? (y/N): " update_confirm
      
      if [[ "$update_confirm" =~ ^[Yy]$ ]]; then
        # Backup current version
        cp "$current_script" "${current_script}.bak" 2>/dev/null || true
        
        # Install new version
        if cp "$tmp_latest" "$current_script" 2>/dev/null; then
          chmod +x "$current_script"
          print_success "Đã cập nhật proxy-manager thành công!"
          echo
          read -p "Nhấn Enter để tiếp tục với phiên bản mới..."
          # Reload script
          exec "$current_script"
        else
          print_error "Không thể cập nhật. Cần quyền root hoặc quyền ghi."
          rm -f "$tmp_latest"
        fi
      else
        rm -f "$tmp_latest"
      fi
    else
      rm -f "$tmp_latest"
    fi
  fi
}

# Function to get script (local first, then download from GitHub)
get_script() {
  local script_name=$1
  local local_path="$SCRIPT_DIR/$script_name"
  local tmp_path="$TMP_SCRIPT_DIR/$script_name"
  local latest_url="$GITHUB_REPO/$script_name"
  
  # Try local first
  if [ -f "$local_path" ]; then
    echo "$local_path"
    return 0
  fi
  
  # Check if we have a cached version and if it's up to date
  if [ -f "$tmp_path" ]; then
    # Check if cached version is recent (less than 1 hour old)
    local cache_age=$(find "$tmp_path" -mmin +60 2>/dev/null | wc -l)
    if [ "$cache_age" -eq 0 ]; then
      echo "$tmp_path"
      return 0
    fi
  fi
  
  # Download from GitHub
  mkdir -p "$TMP_SCRIPT_DIR"
  echo -e "${YELLOW}[+] Đang tải $script_name từ GitHub...${NC}" >&2
  if curl -sSL "$latest_url" -o "$tmp_path" 2>/dev/null; then
    chmod +x "$tmp_path"
    echo "$tmp_path"
    return 0
  else
    # Try cached version if download fails
    if [ -f "$tmp_path" ]; then
      echo "$tmp_path"
      return 0
    fi
    echo ""
    return 1
  fi
}

print_header() {
  echo
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

# Helper function to check if service is installed
is_service_installed() {
  # Check if service file exists (most reliable)
  if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    return 0
  fi
  
  # Fallback: check with systemctl
  if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${SERVICE_NAME}\.service"; then
    return 0
  fi
  
  # Another fallback: try systemctl status (doesn't require service to be running)
  if systemctl status "${SERVICE_NAME}.service" --no-pager >/dev/null 2>&1; then
    return 0
  fi
  
  return 1
}

show_menu() {
  clear
  print_header "3PROXY MANAGER v$VERSION"
  echo "1. Kiểm tra VPS (Check VPS)"
  echo "2. Cài đặt/Tạo proxy mới (Setup Proxy)"
  echo "3. Xem danh sách proxy"
  echo "4. Xem trạng thái service"
  echo "5. Khởi động service"
  echo "6. Dừng service"
  echo "7. Khởi động lại service"
  echo "8. Xem logs"
  echo "9. Test proxy"
  echo "10. Xóa proxy list files"
  echo "0. Thoát"
  echo
}

check_vps() {
  print_header "KIỂM TRA VPS"
  local script_path=$(get_script "check-vps.sh")
  if [ -n "$script_path" ] && [ -f "$script_path" ]; then
    bash "$script_path"
  else
    print_error "Không thể tải script check-vps.sh"
    return 1
  fi
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

setup_proxy() {
  print_header "CÀI ĐẶT PROXY"
  local script_path=$(get_script "setup-proxy.sh")
  if [ -n "$script_path" ] && [ -f "$script_path" ]; then
    bash "$script_path"
  else
    print_error "Không thể tải script setup-proxy.sh"
    return 1
  fi
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

view_proxy_list() {
  print_header "DANH SÁCH PROXY"
  
  local found=0
  
  if [ -f "$PROXY_LIST" ] && [ -s "$PROXY_LIST" ]; then
    found=1
    echo -e "${GREEN}📄 Format: user:pass@ip:port${NC}"
    echo "File: $PROXY_LIST"
    echo "Số lượng: $(wc -l < "$PROXY_LIST") proxy"
    echo
    cat "$PROXY_LIST"
    echo
  fi
  
  if [ -f "$PROXY_LIST_HTTP" ] && [ -s "$PROXY_LIST_HTTP" ]; then
    found=1
    echo -e "${GREEN}📄 Format: http://user:pass@ip:port${NC}"
    echo "File: $PROXY_LIST_HTTP"
    echo "Số lượng: $(wc -l < "$PROXY_LIST_HTTP") proxy"
    echo
    cat "$PROXY_LIST_HTTP"
    echo
  fi
  
  if [ -f "$PROXY_LIST_IPPORT" ] && [ -s "$PROXY_LIST_IPPORT" ]; then
    found=1
    echo -e "${GREEN}📄 Format: ip:port:user:pass${NC}"
    echo "File: $PROXY_LIST_IPPORT"
    echo "Số lượng: $(wc -l < "$PROXY_LIST_IPPORT") proxy"
    echo
    cat "$PROXY_LIST_IPPORT"
    echo
  fi
  
  if [ $found -eq 0 ]; then
    print_warning "Chưa có file proxy list nào. Hãy chạy 'Setup Proxy' trước."
  fi
  
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

view_service_status() {
  print_header "TRẠNG THÁI SERVICE"
  
  if is_service_installed; then
    echo "Service: $SERVICE_NAME"
    echo
    systemctl status "$SERVICE_NAME.service" --no-pager -l || true
  else
    print_warning "Service $SERVICE_NAME chưa được cài đặt."
  fi
  
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

start_service() {
  print_header "KHỞI ĐỘNG SERVICE"
  
  if is_service_installed; then
    if systemctl is-active --quiet "$SERVICE_NAME.service"; then
      print_warning "Service đã đang chạy."
    else
      systemctl start "$SERVICE_NAME.service"
      sleep 1
      if systemctl is-active --quiet "$SERVICE_NAME.service"; then
        print_success "Service đã khởi động thành công."
      else
        print_error "Không thể khởi động service."
        systemctl status "$SERVICE_NAME.service" --no-pager -l | head -n 20
      fi
    fi
  else
    print_error "Service $SERVICE_NAME chưa được cài đặt."
  fi
  
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

stop_service() {
  print_header "DỪNG SERVICE"
  
  if is_service_installed; then
    if ! systemctl is-active --quiet "$SERVICE_NAME.service"; then
      print_warning "Service đã dừng."
    else
      systemctl stop "$SERVICE_NAME.service"
      sleep 1
      if ! systemctl is-active --quiet "$SERVICE_NAME.service"; then
        print_success "Service đã dừng thành công."
      else
        print_error "Không thể dừng service."
      fi
    fi
  else
    print_error "Service $SERVICE_NAME chưa được cài đặt."
  fi
  
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

restart_service() {
  print_header "KHỞI ĐỘNG LẠI SERVICE"
  
  if is_service_installed; then
    systemctl restart "$SERVICE_NAME.service"
    sleep 1
    if systemctl is-active --quiet "$SERVICE_NAME.service"; then
      print_success "Service đã khởi động lại thành công."
    else
      print_error "Service không thể khởi động sau khi restart."
      systemctl status "$SERVICE_NAME.service" --no-pager -l | head -n 20
    fi
  else
    print_error "Service $SERVICE_NAME chưa được cài đặt."
  fi
  
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

view_logs() {
  print_header "LOGS SERVICE"
  
  if is_service_installed; then
    echo "Xem logs gần đây (50 dòng cuối):"
    echo
    journalctl -u "$SERVICE_NAME.service" -n 50 --no-pager || true
    echo
    echo "Log file: /etc/3proxy/logs/3proxy.log"
    if [ -f "/etc/3proxy/logs/3proxy.log" ]; then
      echo "10 dòng cuối của log file:"
      tail -n 10 /etc/3proxy/logs/3proxy.log || true
    fi
  else
    print_error "Service $SERVICE_NAME chưa được cài đặt."
  fi
  
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

test_proxy() {
  print_header "TEST PROXY"
  
  if [ ! -f "$PROXY_LIST" ] || [ ! -s "$PROXY_LIST" ]; then
    print_error "Không tìm thấy file proxy list."
    echo
    read -p "Nhấn Enter để tiếp tục..."
    return 1
  fi
  
  # Get first proxy
  FIRST_PROXY=$(head -n 1 "$PROXY_LIST")
  
  if [ -z "$FIRST_PROXY" ]; then
    print_error "File proxy list trống."
    echo
    read -p "Nhấn Enter để tiếp tục..."
    return 1
  fi
  
  echo "Đang test proxy đầu tiên:"
  echo "Proxy: $FIRST_PROXY"
  echo
  
  # Test with curl
  if command -v curl >/dev/null 2>&1; then
    echo "Test với curl..."
    RESPONSE=$(curl -s --max-time 10 --proxy "http://$FIRST_PROXY" https://api.ipify.org 2>&1)
    if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
      print_success "Proxy hoạt động! IP trả về: $RESPONSE"
    else
      print_error "Proxy không hoạt động hoặc timeout."
      echo "Response: $RESPONSE"
    fi
  else
    print_warning "curl không có, không thể test."
  fi
  
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

delete_proxy_files() {
  print_header "XÓA PROXY LIST FILES"
  
  echo "Các file sẽ bị xóa:"
  [ -f "$PROXY_LIST" ] && echo "  - $PROXY_LIST"
  [ -f "$PROXY_LIST_HTTP" ] && echo "  - $PROXY_LIST_HTTP"
  [ -f "$PROXY_LIST_IPPORT" ] && echo "  - $PROXY_LIST_IPPORT"
  echo
  
  read -p "Bạn có chắc muốn xóa? (y/N): " confirm
  
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -f "$PROXY_LIST" "$PROXY_LIST_HTTP" "$PROXY_LIST_IPPORT"
    print_success "Đã xóa các file proxy list."
  else
    print_info "Đã hủy."
  fi
  
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

# Check for updates on startup
check_update

# Main loop
while true; do
  show_menu
  read -p "Chọn tùy chọn (0-10): " choice
  
  case $choice in
    1)
      check_vps
      ;;
    2)
      setup_proxy
      ;;
    3)
      view_proxy_list
      ;;
    4)
      view_service_status
      ;;
    5)
      start_service
      ;;
    6)
      stop_service
      ;;
    7)
      restart_service
      ;;
    8)
      view_logs
      ;;
    9)
      test_proxy
      ;;
    10)
      delete_proxy_files
      ;;
    0)
      print_info "Thoát..."
      exit 0
      ;;
    *)
      print_error "Tùy chọn không hợp lệ!"
      sleep 1
      ;;
  esac
done

