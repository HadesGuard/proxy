#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly VERSION="1.0.0"
readonly COMMIT_HASH="c3befbf"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
readonly GITHUB_REPO="https://raw.githubusercontent.com/HadesGuard/proxy/main"
readonly SERVICE_NAME="3proxy"
readonly TMP_SCRIPT_DIR="/tmp/proxy-scripts"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly LOG_FILE="/etc/3proxy/logs/3proxy.log"
readonly CONFIG_FILE="/etc/3proxy/3proxy.cfg"

# Proxy file paths
readonly PROXY_LIST="/root/proxies.txt"
readonly PROXY_LIST_HTTP="/root/proxies_http.txt"
readonly PROXY_LIST_IPPORT="/root/proxies_ipport.txt"
readonly PROXY_FILES=(
  "$PROXY_LIST"
  "$PROXY_LIST_HTTP"
  "$PROXY_LIST_IPPORT"
)

# Proxy file formats (matching order with PROXY_FILES)
readonly PROXY_FORMATS=(
  "user:pass@ip:port"
  "http://user:pass@ip:port"
  "ip:port:user:pass"
)
readonly PROXY_FORMAT_TYPES=(
  "USERPASS_AT_HOSTPORT"
  "HTTP_USERPASS_AT_HOSTPORT"
  "HOSTPORT_USERPASS"
)

# GitHub API
readonly GITHUB_REPO_NAME="HadesGuard/proxy"
readonly GITHUB_BRANCH="main"
readonly GITHUB_API_BASE="https://api.github.com/repos/${GITHUB_REPO_NAME}"

# Cache settings
readonly CACHE_MAX_AGE_MINUTES=60

# Service settings
readonly SERVICE_STATUS_LINES=20
readonly LOG_LINES_JOURNALCTL=50
readonly LOG_LINES_FILE=10
readonly SERVICE_CHECK_DELAY=1

# Network settings
readonly PROXY_TEST_TIMEOUT=10
readonly PROXY_TEST_URL="https://api.ipify.org"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

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

wait_for_enter() {
  read -p "Nhấn Enter để tiếp tục..."
}

confirm_action() {
  local prompt="$1"
  read -p "$prompt (y/N): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]]
}

# Common pattern: show header, execute action, wait for enter
execute_with_pause() {
  local header_text="$1"
  shift
  print_header "$header_text"
  "$@"
  echo
  wait_for_enter
}

# Check if a file exists and is not empty
file_exists_and_not_empty() {
  [ -f "$1" ] && [ -s "$1" ]
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

resolve_script_path() {
  local resolved=""

  if command_exists readlink; then
    resolved=$(readlink -f "$SCRIPT_PATH" 2>/dev/null || echo "")
  fi

  if [ -z "$resolved" ] && command_exists realpath; then
    resolved=$(realpath "$SCRIPT_PATH" 2>/dev/null || echo "")
  fi

  if [ -z "$resolved" ]; then
    resolved="$SCRIPT_PATH"
  fi

  echo "$resolved"
}

# ============================================================================
# UPDATE FUNCTIONS
# ============================================================================

get_commit_hash() {
  local script_file="$1"
  if [ -f "$script_file" ]; then
    local hash
    hash=$(grep -m1 "^COMMIT_HASH=" "$script_file" 2>/dev/null | cut -d'"' -f2 || echo "")
    if [ -n "$hash" ]; then
      echo "$hash"
      return 0
    fi
  fi
  echo ""
  return 1
}

get_latest_commit_hash() {
  local api_url="${GITHUB_API_BASE}/commits/${GITHUB_BRANCH}"
  local hash
  hash=$(curl -sSL "$api_url" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | cut -c1-7 || echo "")
  
  if [ -n "$hash" ]; then
    echo "$hash"
    return 0
  fi
  
  echo ""
  return 1
}

is_development_mode() {
  [ "$SCRIPT_DIR" != "/usr/local/bin" ] && [ "$SCRIPT_DIR" != "$HOME/.local/bin" ]
}

download_latest_script() {
  local url="$1"
  local output="$2"
  curl -sSL "$url" -o "$output" 2>/dev/null && [ -f "$output" ]
}

perform_update() {
  local current_script="$1"
  local tmp_latest="$2"
  local current_hash="$3"
  local latest_hash="$4"
  
  # Backup current version
  cp "$current_script" "${current_script}.bak" 2>/dev/null || true
  
  # Install new version
  if cp "$tmp_latest" "$current_script" 2>/dev/null; then
    chmod +x "$current_script"
    if [ -n "$current_hash" ] && [ -n "$latest_hash" ]; then
      print_success "Đã cập nhật proxy-manager từ commit $current_hash lên $latest_hash!"
    else
      print_success "Đã cập nhật proxy-manager thành công!"
    fi
    echo
    wait_for_enter
    exec "$current_script"
  else
    print_error "Không thể cập nhật. Cần quyền root hoặc quyền ghi."
    rm -f "$tmp_latest"
    return 1
  fi
}

check_update_by_hash() {
  local current_script="$1"
  local latest_url="$2"
  local tmp_latest="$3"
  
  local current_hash
  current_hash=$(get_commit_hash "$current_script")
  local latest_hash
  latest_hash=$(get_latest_commit_hash)
  
  # If we don't have both hashes, can't compare
  [ -z "$current_hash" ] || [ -z "$latest_hash" ] && return 1
  
  # Hashes are the same, no update needed
  [ "$current_hash" = "$latest_hash" ] && return 0
  
  # Download new version
  if ! download_latest_script "$latest_url" "$tmp_latest"; then
    return 1
  fi
  
  # Verify the downloaded file has the expected hash (or no hash field)
  local downloaded_hash
  downloaded_hash=$(get_commit_hash "$tmp_latest")
  if [ "$downloaded_hash" != "$latest_hash" ] && [ -n "$downloaded_hash" ]; then
    rm -f "$tmp_latest"
    return 1
  fi
  
  # Show update prompt
  echo
  print_warning "Có phiên bản mới của proxy-manager!"
  echo "  Commit hiện tại: $current_hash"
  echo "  Commit mới:      $latest_hash"
  echo
  
  if confirm_action "Bạn có muốn cập nhật?"; then
    perform_update "$current_script" "$tmp_latest" "$current_hash" "$latest_hash"
  else
    rm -f "$tmp_latest"
  fi
  
  return 0
}

check_update_by_content() {
  local current_script="$1"
  local latest_url="$2"
  local tmp_latest="$3"
  
  if ! download_latest_script "$latest_url" "$tmp_latest"; then
    return 1
  fi
  
  # Files are identical, no update needed
  if [ -f "$current_script" ] && [ -f "$tmp_latest" ] && cmp -s "$current_script" "$tmp_latest"; then
    rm -f "$tmp_latest"
    return 0
  fi
  
  # Files differ, prompt for update
  echo
  print_warning "Có phiên bản mới của proxy-manager!"
  echo "  (Phát hiện bằng so sánh file)"
  echo
  
  if confirm_action "Bạn có muốn cập nhật?"; then
    perform_update "$current_script" "$tmp_latest" "" ""
  else
    rm -f "$tmp_latest"
  fi
}

check_update() {
  # Skip update check if running from local directory (development)
  if is_development_mode; then
    return 0
  fi
  
  # Use realpath to handle symlinks correctly
  local current_script
  current_script=$(resolve_script_path)
  local latest_url="${GITHUB_REPO}/proxy-manager.sh"
  local tmp_latest="/tmp/proxy-manager-latest.sh"
  
  # Try hash-based update first
  if check_update_by_hash "$current_script" "$latest_url" "$tmp_latest"; then
    return 0
  fi
  
  # Fallback: compare file content if hash comparison fails
  check_update_by_content "$current_script" "$latest_url" "$tmp_latest"
}

# Force update script (manual update, works even in development mode)
force_update_script() {
  # Use realpath to handle symlinks correctly
  local current_script
  current_script=$(resolve_script_path)
  local latest_url="${GITHUB_REPO}/proxy-manager.sh"
  local tmp_latest="/tmp/proxy-manager-latest.sh"
  
  print_header "CẬP NHẬT SCRIPT CHÍNH"
  
  echo "Đang kiểm tra phiên bản mới..."
  echo
  
  # Always try to download latest version
  if ! download_latest_script "$latest_url" "$tmp_latest"; then
    print_error "Không thể tải phiên bản mới từ GitHub."
    echo
    wait_for_enter
    return 1
  fi
  
  # Get hashes for comparison
  local current_hash
  current_hash=$(get_commit_hash "$current_script")
  local latest_hash
  latest_hash=$(get_commit_hash "$tmp_latest")
  
  # If hashes are the same, still offer to update (force mode)
  if [ -n "$current_hash" ] && [ -n "$latest_hash" ] && [ "$current_hash" = "$latest_hash" ]; then
    print_info "Bạn đang sử dụng phiên bản mới nhất (commit: $current_hash)"
    echo
    if ! confirm_action "Bạn vẫn muốn cập nhật lại?"; then
      rm -f "$tmp_latest"
      echo
      wait_for_enter
      return 0
    fi
  fi
  
  # Show update info
  if [ -n "$current_hash" ] && [ -n "$latest_hash" ]; then
    echo "  Commit hiện tại: $current_hash"
    echo "  Commit mới:      $latest_hash"
    echo
  fi
  
  if [ -z "$current_hash" ] || [ -z "$latest_hash" ] || [ "$current_hash" != "$latest_hash" ]; then
    print_warning "Có phiên bản mới!"
    echo
  fi
  
  if confirm_action "Bạn có muốn cập nhật script?"; then
    perform_update "$current_script" "$tmp_latest" "$current_hash" "$latest_hash"
  else
    rm -f "$tmp_latest"
    print_info "Đã hủy cập nhật."
    echo
    wait_for_enter
  fi
}

# ============================================================================
# SCRIPT MANAGEMENT FUNCTIONS
# ============================================================================

is_cache_valid() {
  local file_path="$1"
  [ -f "$file_path" ] && ! find "$file_path" -mmin +${CACHE_MAX_AGE_MINUTES} 2>/dev/null | grep -q .
}

get_script() {
  local script_name="$1"
  local force_download="${2:-false}"
  local local_path="${SCRIPT_DIR}/${script_name}"
  local tmp_path="${TMP_SCRIPT_DIR}/${script_name}"
  local latest_url="${GITHUB_REPO}/${script_name}"
  
  # Try local first (unless forcing download)
  if [ "$force_download" != "true" ] && [ -f "$local_path" ]; then
    echo "$local_path"
    return 0
  fi
  
  # Check if we have a valid cached version (unless forcing download)
  if [ "$force_download" != "true" ] && is_cache_valid "$tmp_path"; then
    echo "$tmp_path"
    return 0
  fi
  
  # Download from GitHub
  mkdir -p "$TMP_SCRIPT_DIR"
  if [ "$force_download" = "true" ]; then
    echo -e "${YELLOW}[+] Đang tải lại ${script_name} từ GitHub...${NC}" >&2
  else
    echo -e "${YELLOW}[+] Đang tải ${script_name} từ GitHub...${NC}" >&2
  fi
  
  if download_latest_script "$latest_url" "$tmp_path"; then
    chmod +x "$tmp_path"
    echo "$tmp_path"
    return 0
  fi
  
  # Fallback to cached version if download fails (even if expired)
  if [ -f "$tmp_path" ]; then
    echo "$tmp_path"
    return 0
  fi
  
  echo ""
  return 1
}

# List of external scripts that can be updated
get_external_scripts() {
  echo "check-vps.sh setup-proxy.sh"
}

# Force update all external scripts
force_update_external_scripts() {
  print_header "CẬP NHẬT CÁC SCRIPT LIÊN QUAN"
  
  local scripts
  scripts=$(get_external_scripts)
  local updated=0
  local failed=0
  
  for script_name in $scripts; do
    echo -n "Đang cập nhật ${script_name}... "
    
    # Force download (ignore cache)
    local script_path
    script_path=$(get_script "$script_name" "true")
    
    if [ -n "$script_path" ] && [ -f "$script_path" ]; then
      print_success "Thành công"
      updated=$((updated + 1))
    else
      print_error "Thất bại"
      failed=$((failed + 1))
    fi
  done
  
  echo
  echo "Kết quả:"
  echo "  ✅ Cập nhật thành công: $updated"
  echo "  ❌ Cập nhật thất bại: $failed"
  echo
  
  if [ $updated -gt 0 ]; then
    print_success "Đã cập nhật $updated script(s)!"
  fi
  
  if [ $failed -gt 0 ]; then
    print_warning "Có $failed script(s) không thể cập nhật."
  fi
  
  echo
  wait_for_enter
}

# Clear cache for all scripts
clear_script_cache() {
  print_header "XÓA CACHE SCRIPT"
  
  if [ ! -d "$TMP_SCRIPT_DIR" ]; then
    print_info "Không có cache để xóa."
    echo
    wait_for_enter
    return 0
  fi
  
  local cache_count
  cache_count=$(find "$TMP_SCRIPT_DIR" -type f 2>/dev/null | wc -l)
  
  if [ "$cache_count" -eq 0 ]; then
    print_info "Không có cache để xóa."
    echo
    wait_for_enter
    return 0
  fi
  
  echo "Các file cache sẽ bị xóa:"
  find "$TMP_SCRIPT_DIR" -type f 2>/dev/null | while read -r file; do
    echo "  - $file"
  done
  echo
  
  if confirm_action "Bạn có chắc muốn xóa cache?"; then
    rm -rf "$TMP_SCRIPT_DIR"
    print_success "Đã xóa cache thành công!"
  else
    print_info "Đã hủy."
  fi
  
  echo
  wait_for_enter
}

# Update all scripts (main + external)
update_all_scripts() {
  print_header "CẬP NHẬT TẤT CẢ SCRIPT"
  
  echo "Tùy chọn cập nhật:"
  echo "1. Cập nhật script chính (proxy-manager.sh)"
  echo "2. Cập nhật các script liên quan (check-vps.sh, setup-proxy.sh)"
  echo "3. Cập nhật tất cả"
  echo "4. Xóa cache và cập nhật lại"
  echo "0. Hủy"
  echo
  
  read -p "Chọn tùy chọn (0-4): " update_choice
  
  case "$update_choice" in
    1)
      force_update_script
      ;;
    2)
      force_update_external_scripts
      ;;
    3)
      force_update_external_scripts
      echo
      force_update_script
      ;;
    4)
      clear_script_cache
      echo
      force_update_external_scripts
      echo
      force_update_script
      ;;
    0)
      print_info "Đã hủy."
      echo
      wait_for_enter
      ;;
    *)
      print_error "Tùy chọn không hợp lệ!"
      echo
      wait_for_enter
      ;;
  esac
}

run_external_script() {
  local script_name="$1"
  local header_text="$2"
  
  print_header "$header_text"
  local script_path
  script_path=$(get_script "$script_name")
  
  if [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
    print_error "Không thể tải script ${script_name}"
    echo
    wait_for_enter
    return 1
  fi
  
  bash "$script_path"
  echo
  wait_for_enter
}

# ============================================================================
# SERVICE MANAGEMENT FUNCTIONS
# ============================================================================

is_service_installed() {
  local service_full_name
  service_full_name=$(get_service_full_name)
  
  # Check if service file exists (most reliable)
  [ -f "$SERVICE_FILE" ] && return 0
  
  # Fallback: check with systemctl
  systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${service_full_name}" && return 0
  
  # Another fallback: try systemctl status (doesn't require service to be running)
  systemctl status "$service_full_name" --no-pager >/dev/null 2>&1 && return 0
  
  return 1
}

is_service_active() {
  local service_full_name
  service_full_name=$(get_service_full_name)
  systemctl is-active --quiet "$service_full_name"
}

require_service_installed() {
  if ! is_service_installed; then
    print_error "Service ${SERVICE_NAME} chưa được cài đặt."
    return 1
  fi
  return 0
}

get_service_full_name() {
  echo "${SERVICE_NAME}.service"
}

manage_service() {
  local action="$1"  # start, stop, restart
  local header_text="$2"
  local success_msg="$3"
  local already_state_msg="$4"
  
  print_header "$header_text"
  
  if ! require_service_installed; then
    echo
    wait_for_enter
    return 1
  fi
  
  local service_full_name
  service_full_name=$(get_service_full_name)
  
  case "$action" in
    start)
      if is_service_active; then
        print_warning "$already_state_msg"
      else
        systemctl start "$service_full_name"
        sleep ${SERVICE_CHECK_DELAY}
        if is_service_active; then
          print_success "$success_msg"
        else
          print_error "Không thể khởi động service."
          systemctl status "$service_full_name" --no-pager -l | head -n ${SERVICE_STATUS_LINES}
        fi
      fi
      ;;
    stop)
      if ! is_service_active; then
        print_warning "$already_state_msg"
      else
        systemctl stop "$service_full_name"
        sleep ${SERVICE_CHECK_DELAY}
        if ! is_service_active; then
          print_success "$success_msg"
        else
          print_error "Không thể dừng service."
        fi
      fi
      ;;
    restart)
      systemctl restart "$service_full_name"
      sleep ${SERVICE_CHECK_DELAY}
      if is_service_active; then
        print_success "$success_msg"
      else
        print_error "Service không thể khởi động sau khi restart."
        systemctl status "$service_full_name" --no-pager -l | head -n ${SERVICE_STATUS_LINES}
      fi
      ;;
  esac
  
  echo
  wait_for_enter
}

start_service() {
  manage_service "start" \
    "KHỞI ĐỘNG SERVICE" \
    "Service đã khởi động thành công." \
    "Service đã đang chạy."
}

stop_service() {
  manage_service "stop" \
    "DỪNG SERVICE" \
    "Service đã dừng thành công." \
    "Service đã dừng."
}

restart_service() {
  manage_service "restart" \
    "KHỞI ĐỘNG LẠI SERVICE" \
    "Service đã khởi động lại thành công." \
    ""
}

view_service_status() {
  print_header "TRẠNG THÁI SERVICE"
  
  if is_service_installed; then
    local service_full_name
    service_full_name=$(get_service_full_name)
    echo "Service: $SERVICE_NAME"
    echo
    systemctl status "$service_full_name" --no-pager -l || true
  else
    print_warning "Service ${SERVICE_NAME} chưa được cài đặt."
  fi
  
  echo
  wait_for_enter
}

view_logs() {
  print_header "LOGS SERVICE"
  
  if ! require_service_installed; then
    echo
    wait_for_enter
    return 1
  fi
  
  local service_full_name
  service_full_name=$(get_service_full_name)
  
  echo "Xem logs gần đây (${LOG_LINES_JOURNALCTL} dòng cuối):"
  echo
  journalctl -u "$service_full_name" -n ${LOG_LINES_JOURNALCTL} --no-pager || true
  echo
  echo "Log file: ${LOG_FILE}"
  if [ -f "$LOG_FILE" ]; then
    echo "${LOG_LINES_FILE} dòng cuối của log file:"
    tail -n ${LOG_LINES_FILE} "$LOG_FILE" || true
  fi
  
  echo
  wait_for_enter
}

view_proxy_config() {
  print_header "CẤU HÌNH 3PROXY"
  
  echo "File cấu hình: ${CONFIG_FILE}"
  echo
  
  if file_exists_and_not_empty "$CONFIG_FILE"; then
    cat "$CONFIG_FILE" || {
      print_error "Không thể đọc file cấu hình. Có thể do quyền truy cập."
      echo
      wait_for_enter
      return 1
    }
  else
    print_warning "Không tìm thấy hoặc file rỗng: ${CONFIG_FILE}"
  fi
  
  echo
  wait_for_enter
}

# ============================================================================
# PROXY MANAGEMENT FUNCTIONS
# ============================================================================

check_vps() {
  run_external_script "check-vps.sh" "KIỂM TRA VPS"
}

setup_proxy() {
  run_external_script "setup-proxy.sh" "CÀI ĐẶT PROXY"
}

display_proxy_file() {
  local file_path="$1"
  local format="$2"
  
  if file_exists_and_not_empty "$file_path"; then
    echo -e "${GREEN}📄 Format: ${format}${NC}"
    echo "File: $file_path"
    local line_count
    line_count=$(wc -l < "$file_path" 2>/dev/null || echo "0")
    echo "Số lượng: $line_count proxy"
    echo
    cat "$file_path" || {
      print_error "Không thể đọc file. Có thể do quyền truy cập."
      return 1
    }
    echo
    return 0
  fi
  return 1
}

view_proxy_list() {
  print_header "DANH SÁCH PROXY"
  
  local found=0
  local i
  
  # Iterate through proxy files array
  for i in "${!PROXY_FILES[@]}"; do
    display_proxy_file "${PROXY_FILES[$i]}" "${PROXY_FORMATS[$i]}" && found=1
  done
  
  if [ $found -eq 0 ]; then
    print_warning "Chưa có file proxy list nào. Hãy chạy 'Setup Proxy' trước."
  fi
  
  echo
  wait_for_enter
}

parse_proxy_entry() {
  local entry="$1"
  local format_type="$2"
  local original_entry="$1"
  entry=${entry//$'\r'/}
  entry=${entry//$'\n'/}
  entry=${entry//$'\t'/}
  entry=${entry//[$'\r']/}
  entry=$(echo "$entry" | xargs 2>/dev/null || echo "$entry")

  local scheme="http"
  local host_port=""
  local credentials=""

  case "$format_type" in
    "USERPASS_AT_HOSTPORT")
      if [[ "$entry" != *@* ]]; then
        print_error "Không nhận diện được proxy: $original_entry"
        return 1
      fi
      local creds="${entry%@*}"
      host_port="${entry#*@}"
      if [[ "$creds" != *:* ]]; then
        print_error "Proxy thiếu user/pass: $original_entry"
        return 1
      fi
      credentials="${creds%%:*}:${creds#*:}"
      ;;
    "HTTP_USERPASS_AT_HOSTPORT")
      local trimmed="${entry#http://}"
      trimmed="${trimmed#HTTP://}"
      if [[ "$trimmed" != *@* ]]; then
        print_error "Không nhận diện được proxy: $original_entry"
        return 1
      fi
      local creds="${trimmed%@*}"
      host_port="${trimmed#*@}"
      if [[ "$creds" != *:* ]]; then
        print_error "Proxy thiếu user/pass: $original_entry"
        return 1
      fi
      credentials="${creds%%:*}:${creds#*:}"
      ;;
    "HOSTPORT_USERPASS")
      IFS=':' read -r host port user pass <<< "$entry"
      if [ -z "$host" ] || [ -z "$port" ] || [ -z "$user" ] || [ -z "$pass" ]; then
        print_error "Proxy không đúng định dạng: $original_entry"
        return 1
      fi
      host_port="$host:$port"
      credentials="$user:$pass"
      ;;
    *)
      print_error "Định dạng proxy không được hỗ trợ: $format_type"
      return 1
      ;;
  esac

  if [ -z "$host_port" ]; then
    print_error "Không xác định được host:port từ proxy: $original_entry"
    return 1
  fi

  echo "${scheme};${host_port};${credentials}"
}

mask_proxy_display() {
  local credentials="$1"
  local host_port="$2"
  if [ -z "$credentials" ]; then
    echo "$host_port"
    return 0
  fi
  local user="${credentials%%:*}"
  if [ -z "$user" ]; then
    echo "****@$host_port"
  else
    echo "${user}:****@$host_port"
  fi
}

test_proxy() {
  print_header "TEST PROXY"
  
  local available_files=()
  local available_formats=()
  local available_format_types=()
  local available_counts=()
  local i

  for i in "${!PROXY_FILES[@]}"; do
    local file="${PROXY_FILES[$i]}"
    if file_exists_and_not_empty "$file"; then
      available_files+=("$file")
      available_formats+=("${PROXY_FORMATS[$i]}")
      available_format_types+=("${PROXY_FORMAT_TYPES[$i]}")
      local count
      count=$(wc -l < "$file" 2>/dev/null || echo "0")
      available_counts+=("$count")
    fi
  done

  if [ ${#available_files[@]} -eq 0 ]; then
    print_error "Không tìm thấy proxy list để test. Hãy chạy 'Setup Proxy' trước."
    echo
    wait_for_enter
    return 1
  fi

  if ! is_service_active; then
    print_warning "Service 3proxy hiện không chạy. Kết quả test có thể thất bại."
    echo
  fi

  if ! command_exists curl; then
    print_warning "curl không có, không thể test proxy."
    echo
    wait_for_enter
    return 1
  fi

  echo "Chọn nguồn proxy để test:"
  for i in "${!available_files[@]}"; do
    local option=$((i + 1))
    echo "  $option. ${available_formats[$i]} (file: ${available_files[$i]}, ${available_counts[$i]} dòng)"
  done
  echo "  0. Hủy"
  echo

  local selection
  read -p "Lựa chọn (0-${#available_files[@]}, mặc định 1): " selection
  if [ -z "$selection" ]; then
    selection=1
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
    print_error "Lựa chọn không hợp lệ."
    echo
    wait_for_enter
    return 1
  fi

  if [ "$selection" -eq 0 ]; then
    print_info "Đã hủy test proxy."
    echo
    wait_for_enter
    return 0
  fi

  if [ "$selection" -lt 1 ] || [ "$selection" -gt ${#available_files[@]} ]; then
    print_error "Lựa chọn vượt phạm vi."
    echo
    wait_for_enter
    return 1
  fi

  local selected_index=$((selection - 1))
  local selected_file="${available_files[$selected_index]}"
  local selected_format="${available_formats[$selected_index]}"
  local selected_format_type="${available_format_types[$selected_index]}"
  local selected_count="${available_counts[$selected_index]}"

  echo
  echo "File: $selected_file"
  echo "Định dạng: $selected_format"
  echo "Số lượng proxy: $selected_count"
  echo

  if [ "$selected_count" -eq 0 ]; then
    print_error "Không có dòng hợp lệ trong file proxy."
    echo
    wait_for_enter
    return 1
  fi

  local proxy_line_index
  read -p "Chọn số thứ tự proxy để test (1-$selected_count, mặc định 1): " proxy_line_index
  if [ -z "$proxy_line_index" ]; then
    proxy_line_index=1
  fi

  if ! [[ "$proxy_line_index" =~ ^[0-9]+$ ]]; then
    print_error "Số thứ tự không hợp lệ."
    echo
    wait_for_enter
    return 1
  fi

  if [ "$proxy_line_index" -lt 1 ] || [ "$proxy_line_index" -gt "$selected_count" ]; then
    print_error "Số thứ tự vượt phạm vi."
    echo
    wait_for_enter
    return 1
  fi

  local proxy_entry
  proxy_entry=$(sed -n "${proxy_line_index}p" "$selected_file" 2>/dev/null || echo "")
  if [ -z "$proxy_entry" ]; then
    print_error "Không thể đọc proxy ở dòng $proxy_line_index."
    echo
    wait_for_enter
    return 1
  fi

  local parsed
  parsed=$(parse_proxy_entry "$proxy_entry" "$selected_format_type") || {
    echo
    wait_for_enter
    return 1
  }

  IFS=';' read -r proxy_scheme proxy_host_port proxy_credentials <<< "$parsed"

  local masked_display
  masked_display=$(mask_proxy_display "$proxy_credentials" "$proxy_host_port")

  echo
  echo "Đang test proxy dòng $proxy_line_index: $masked_display"
  echo "Endpoint test: ${PROXY_TEST_URL}"
  echo

  local curl_cmd=(curl -s --max-time "${PROXY_TEST_TIMEOUT}" --proxy "${proxy_scheme}://${proxy_host_port}")
  if [ -n "$proxy_credentials" ]; then
    curl_cmd+=(--proxy-user "$proxy_credentials")
  fi
  curl_cmd+=("${PROXY_TEST_URL}")

  local response
  response=$("${curl_cmd[@]}" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
    if [[ "$response" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      print_success "Proxy hoạt động! IP trả về: $response"
    else
      print_success "Proxy phản hồi thành công: $response"
    fi
  else
    print_error "Proxy không hoạt động hoặc timeout (exit code: $exit_code)."
    echo "Chi tiết phản hồi:"
    echo "$response"
  fi
  
  echo
  wait_for_enter
}

delete_proxy_files() {
  print_header "XÓA PROXY LIST FILES"
  
  echo "Các file sẽ bị xóa:"
  local file
  for file in "${PROXY_FILES[@]}"; do
    [ -f "$file" ] && echo "  - $file"
  done
  echo
  
  if confirm_action "Bạn có chắc muốn xóa?"; then
    rm -f "${PROXY_FILES[@]}"
    print_success "Đã xóa các file proxy list."
  else
    print_info "Đã hủy."
  fi
  
  echo
  wait_for_enter
}

# ============================================================================
# MENU FUNCTIONS
# ============================================================================

show_menu() {
  clear
  print_header "3PROXY MANAGER v${VERSION}"
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
  echo "11. Xem cấu hình 3proxy"
  echo "12. Cập nhật script"
  echo "0. Thoát"
  echo
}

handle_menu_choice() {
  local choice="$1"
  
  case "$choice" in
    1) check_vps ;;
    2) setup_proxy ;;
    3) view_proxy_list ;;
    4) view_service_status ;;
    5) start_service ;;
    6) stop_service ;;
    7) restart_service ;;
    8) view_logs ;;
    9) test_proxy ;;
    10) delete_proxy_files ;;
    11) view_proxy_config ;;
    12) update_all_scripts ;;
    0)
      print_info "Thoát..."
      exit 0
      ;;
    *)
      print_error "Tùy chọn không hợp lệ!"
      sleep 1
      ;;
  esac
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  # Check for updates on startup
  check_update
  
  # Main loop
  while true; do
    show_menu
    read -p "Chọn tùy chọn (0-12): " choice
    handle_menu_choice "$choice"
  done
}

main "$@"
