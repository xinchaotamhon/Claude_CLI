# Chính sách kiểm tra và cập nhật

## Claude Code binary đóng nguồn

`bin/claude.exe` được kiểm tra bằng version, SHA-256 và release notes chính
thức. Không có source diff. Folder đặt `DISABLE_AUTOUPDATER=1`; không tự thay
binary khi khởi động hoặc kiểm tra.

## Claude Code Router mã nguồn mở

Operational package được pin trong `provider_router/package.json`. Source,
license và reviewed commit nằm trong `provider_router/SOURCE.json`. Runtime
Node và `node_modules` bị Git ignore nhưng có thể tái tạo bằng lệnh explicit:

```text
RUN_CLAUDE.bat --install-router
```

Lệnh trên cần Node/npm có sẵn đúng một lần và chỉ ghi vào `provider_router`.
Nó không cài global. Bình thường không cần Node/npm bên ngoài nữa.

## Review update

```text
RUN_CLAUDE.bat --check-updates
RUN_CLAUDE.bat --fetch-router-source
```

Lệnh đầu hiển thị local version/hash và release metadata. Lệnh thứ hai fetch
`upstream/main` trong source fork `claude-code-router_proxy`, rồi hiển thị
commit và diff stat từ pinned source commit đến upstream. Working tree/branch
`claude` không bị merge, rebase hay checkout; runtime và config không thay đổi.

Chỉ nâng khi cần tính năng/sửa lỗi thực sự. Trước khi đổi version:

1. Đọc release notes và source diff, đặc biệt protocol transformer, tool calls,
   streaming, auth, config paths và listener binding.
2. Sửa version trong package/source records bằng một decision rõ ràng.
3. Chạy installer explicit.
4. Chạy toàn bộ smoke gates trên cùng artifact.
5. Chỉ chạy provider smoke nhỏ khi chủ máy cho phép quota/network.

Rollback là khôi phục version pin cũ, chạy installer explicit và chạy lại gate.
Không dùng auto-merge hay cập nhật theo `latest` chỉ vì có release mới.
