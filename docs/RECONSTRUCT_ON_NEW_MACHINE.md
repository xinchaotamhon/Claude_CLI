# Dựng lại trên máy Windows mới

Tài liệu này là đường tái tạo chuẩn khi chỉ còn repository Git. Mọi lệnh cài đặt
đều là thao tác chủ động; `DASHBOARD.bat` không tự tải, tự merge hay tự thay
binary. Bản khóa máy đọc được nằm tại `DEPENDENCIES.lock.json`.

## Những gì Git giữ và không giữ

Git giữ source dashboard, script, lockfile, provenance, patch và tài liệu. Git
không giữ binary đóng nguồn, Node/module runtime lớn, OAuth/API key, DPAPI,
database CCR hoặc nội dung session. Vì vậy một máy mới có thể dựng đúng phần
mềm nhưng phải đăng nhập lại tài khoản. Không sao chép DPAPI ciphertext sang
Windows user khác vì nó không giải mã được.

## Trình tự cho AI trên máy mới

1. Clone `https://github.com/xinchaotamhon/Claude_CLI.git`, checkout branch
   `claude`, rồi đọc `START_HERE.md` theo đúng read order.
2. Chạy `tools/audit_reconstruction.ps1`. Chỉ cài các mục báo thiếu.
3. Chạy `tools/install_router_runtime.ps1` để tạo Node + CCR project-local và
   áp dụng patch provider-only đã pin.
4. Chạy `tools/install_codex_login_runtime.ps1` nếu cần đăng nhập ChatGPT/Codex.
5. Chạy `tools/install_challenger_pilot.ps1` nếu cần Google OAuth/challenger.
   Script clone đúng upstream/tag, áp dụng ba patch tracked và build binary có
   hash kiểm chứng; không cần tin một binary được commit vào Git.
6. Tải Claude Code Windows native binary từ nguồn Anthropic chính thức sau khi
   chủ máy duyệt. Đặt tại `bin/claude.exe`, chạy `tools/audit_reconstruction.ps1`
   và so SHA-256 với `checksums/claude.exe.sha256`. Nếu là bản mới, không sửa
   checksum âm thầm: đọc release notes, chạy gate, ghi evidence rồi mới promote.
7. Sao chép `setting.example.json` thành `setting.json` nếu dùng API key tùy
   chỉnh. Không đưa key vào file tracked.
8. Chạy toàn bộ smoke gates, sau đó mở `DASHBOARD.bat` và đăng nhập lại từng
   Codex/Google account bằng browser chính thức.

## Source fork và cập nhật

- CCR có fork riêng `xinchaotamhon/claude-code-router_proxy`, branch `claude`.
- CLIProxyAPI được tái tạo từ upstream pin + bốn patch được parent Git giữ. Bản
  nested checkout chỉ là workspace độc lập bị ignore; mất nó không làm mất
  thay đổi của dự án. Khi owner tạo fork CLIProxyAPI riêng, thêm `origin` và
  push branch `claude`; vẫn giữ patch series trong parent làm nguồn tái tạo.
- Dashboard chỉ gọi GitHub khi bấm **Kiểm tra cập nhật**. Nó hiển thị local,
  latest và ngày đã cập nhật/duyệt gần nhất; không fetch source, merge hay thay
  runtime.

## Session và tính độc lập thực tế

Session mới dùng chung vùng riêng `.runtime/claude-home`; chỉ mục thân thiện nằm
ở `.runtime/claude-sessions/index.json`. Dashboard sao chép session cũ từ các
mode CCR vào vùng này mà không đọc nội dung và không xóa nguồn. Toàn bộ `.runtime`
bị ignore vì session có thể chứa mã nguồn, hội thoại và dữ liệu riêng tư.

“Độc lập” nghĩa là launcher chọn executable/config/state trong project. Git,
PowerShell 7+, browser, chứng thư TLS và dịch vụ OpenAI/Google/Anthropic vẫn là phụ
thuộc hệ điều hành hoặc mạng và được khai báo rõ; chúng không thể được nhúng an
toàn vào repository.
