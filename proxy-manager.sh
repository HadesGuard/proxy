#!/usr/bin/env bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check-vps.sh"
SETUP_SCRIPT="$SCRIPT_DIR/setup-proxy.sh"
PROXY_LIST="/root/proxies.txt"
PROXY_LIST_HTTP="/root/proxies_http.txt"
PROXY_LIST_IPPORT="/root/proxies_ipport.txt"
SERVICE_NAME="3proxy"

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

show_menu() {
  clear
  print_header "3PROXY MANAGER"
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
  if [ -f "$CHECK_SCRIPT" ]; then
    bash "$CHECK_SCRIPT"
  else
    print_error "Không tìm thấy script check-vps.sh"
    return 1
  fi
  echo
  read -p "Nhấn Enter để tiếp tục..."
}

setup_proxy() {
  print_header "CÀI ĐẶT PROXY"
  if [ -f "$SETUP_SCRIPT" ]; then
    bash "$SETUP_SCRIPT"
  else
    print_error "Không tìm thấy script setup-proxy.sh"
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
  
  if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
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
  
  if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
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
  
  if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
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
  
  if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
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
  
  if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
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

