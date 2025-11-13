# 3Proxy Manager

Quản lý 3proxy với menu tương tác đơn giản.

## Quick Setup (1 command)

**System-wide (cần sudo):**
```bash
curl -sSL https://raw.githubusercontent.com/HadesGuard/proxy/main/proxy-manager.sh -o /tmp/proxy-manager.sh && chmod +x /tmp/proxy-manager.sh && sudo mv /tmp/proxy-manager.sh /usr/local/bin/proxy-manager
```

**User-only (không cần sudo):**
```bash
mkdir -p ~/.local/bin && curl -sSL https://raw.githubusercontent.com/HadesGuard/proxy/main/proxy-manager.sh -o ~/.local/bin/proxy-manager && chmod +x ~/.local/bin/proxy-manager && echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

Hoặc nếu bạn đã clone repo:

```bash
chmod +x proxy-manager.sh && sudo ln -sf $(pwd)/proxy-manager.sh /usr/local/bin/proxy-manager
```

## Sử dụng

Sau khi setup, chạy:

```bash
proxy-manager
```

## Tính năng

- ✅ Kiểm tra VPS
- ✅ Cài đặt/Tạo proxy mới
- ✅ Xem danh sách proxy (3 formats)
- ✅ Quản lý service (start/stop/restart)
- ✅ Xem logs
- ✅ Test proxy
- ✅ Xóa proxy list files

## Files

- `check-vps.sh` - Kiểm tra VPS và đề xuất số lượng proxy
- `setup-proxy.sh` - Cài đặt 3proxy và tạo proxy
- `proxy-manager.sh` - Menu quản lý chính
- `update-commit-hash.sh` - Script để update commit hash (tự động chạy qua git hook)

## Auto Update

Script `proxy-manager.sh` tự động kiểm tra update mỗi lần chạy bằng cách:
- So sánh commit hash hiện tại với commit hash mới nhất trên GitHub
- Sử dụng GitHub API để lấy latest commit hash
- Tự động phát hiện update ngay cả khi quên tăng version number

**Lưu ý:** Trước khi commit, chạy `./update-commit-hash.sh` để update commit hash vào script (hoặc dùng git pre-commit hook tự động).

