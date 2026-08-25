# Claude CLI multi-provider router — local runbook

## Hai file người dùng thao tác

1. `setting.json`: tự nhập API endpoint/key/model và route chạy Claude.
2. `SIGN_ACCOUNT.bat`: đăng nhập từng tài khoản Codex vào home riêng trong dự
   án. File này không mở giao diện agent/profile của CCR.

`RUN_CLAUDE.bat` chỉ đồng bộ file đã thay đổi, hiện profile được bật và chạy
Claude. Nó không còn hỏi nhập API, URL, provider, model hoặc CCR client key.

## Sửa setting.json

`setting.json` dùng JSON chuẩn, không có comment. File được Git ignore vì API
key là plaintext theo lựa chọn của chủ máy. Khi cần hỏi AI sửa schema, gửi
`setting.example.json`; không gửi file thật sau khi đã điền key.

Provider tối thiểu:

```json
{
  "id": "deepseek-main",
  "name": "DeepSeek",
  "enabled": true,
  "base_url": "https://api.deepseek.com",
  "protocol": "openai_chat_completions",
  "api_key": "PASTE_YOUR_KEY_HERE",
  "credentials": [],
  "models": ["deepseek-chat", "deepseek-reasoner"],
  "extra_headers": {},
  "extra_body": {}
}
```

Profile tương ứng:

```json
{
  "id": "deepseek-reasoner",
  "name": "DeepSeek Reasoner",
  "enabled": true,
  "provider": "DeepSeek",
  "model": "deepseek-reasoner",
  "background_model": "deepseek-chat",
  "think_model": "deepseek-reasoner",
  "long_context_model": "deepseek-reasoner"
}
```

`provider` trong profile phải giống chính xác `name` của provider trong
`setting.json` hoặc tên provider/account được import trong CCR UI.

Protocol được chấp nhận:

- `anthropic_messages`
- `openai_chat_completions`
- `openai_responses`
- `gemini_generate_content`
- `gemini_interactions`

Một provider có nhiều API key có thể dùng `credentials`:

```json
"api_key": "",
"credentials": [
  {
    "name": "Account 1",
    "api_key": "FIRST_KEY",
    "enabled": true,
    "priority": 1,
    "weight": 1
  },
  {
    "name": "Account 2",
    "api_key": "SECOND_KEY",
    "enabled": true,
    "priority": 2,
    "weight": 1
  }
]
```

CCR chọn key theo credential-pool policy của nó. Đây là API key pool, không
phải vòng quay tài khoản website.

## Đồng bộ thực sự vào CCR

CCR 3.0.21 lưu cấu hình sống trong SQLite, không theo dõi JSON. Launcher xử lý
điểm này như sau:

1. Đọc và validate toàn bộ `setting.json` trước khi thay đổi CCR.
2. So SHA-256 với lần áp dụng trước; không đổi thì bỏ qua RPC để mở menu nhanh.
3. Khởi động management service không gateway trên `127.0.0.1:3458`.
4. Xác minh state/PID/Node/command line/service token.
5. Gọi authenticated `getConfig`, giữ các provider/account không do file quản
   lý, rồi thay nhóm ID `local-setting--*`.
6. Ép gateway về `127.0.0.1:3456`; tắt proxy, system proxy, network capture,
   request log và built-in Codex routing rule.
7. Xóa mọi CCR agent profile trước khi save. Lựa chọn `System default` của CCR
   có thể ghi vào `~/.codex/config.toml`; `CLI & APP` còn có thể nối desktop app.
   Project này chỉ dùng CCR làm HTTP gateway nên không cho phép hai cơ chế đó.
8. Gọi `saveConfig` với profile cleanup để CCR khôi phục takeover cũ nếu có.
9. Tự lấy/tạo CCR client key và lưu bằng Windows DPAPI.

Lệnh nền `ccr start` đôi khi có thể trả mã khác 0 sau khi đã kích hoạt gateway.
Launcher không coi riêng mã đó là thành công hay thất bại: nó kiểm tra lại state,
PID, đúng Node/CLI cục bộ, service token và `/health` trên loopback. Nếu toàn bộ
hậu điều kiện này đạt thì tiếp tục; nếu không đạt thì dừng trước khi giải mã
client key và báo cả ngữ cảnh start lẫn lỗi xác minh.

Nếu file JSON sai, URL chứa credential, protocol sai, provider trùng tên hoặc
provider bật mà thiếu key/model, việc save không diễn ra.

## Nhập tài khoản với SIGN_ACCOUNT.bat

Màn hình Add Provider chuẩn không thấy Codex import trong dự án này vì CCR tìm
login tại `CCR_INTERNAL_HOME_DIR/.codex/auth.json`, còn home của router đã được
cô lập trong folder. Đây là nguyên nhân panel import tự ẩn.

Double-click `SIGN_ACCOUNT.bat`:

- `[1]`: đặt tên tài khoản, mở trang đăng nhập OpenAI chính thức và tự hoàn tất
  password/2FA. Mỗi lần chạy tạo một `CODEX_HOME` riêng dưới
  `provider_router/.ccr-local/codex-accounts`; route tự xuất hiện trong
  `RUN_CLAUDE.bat` mà không cần thêm provider vào `setting.json`.
- `[R]`: chọn tài khoản đã nhập, kiểm tra lại các model ứng viên và tạo lại mỗi
  model dùng được thành một route RUN riêng; không đăng nhập browser lại. Mỗi
  kiểm tra là request thật rất nhỏ nên có thể tiêu một lượng quota nhỏ.
- `[L]`: chỉ liệt kê tên các tài khoản Codex đã nhập.

API key/endpoint Gemini, DeepSeek, OpenRouter, OpenAI API hoặc custom chỉ cấu
hình trong ignored `setting.json`. Không dùng trang `Connect agent` của CCR.

Để nhập tài khoản Codex thứ hai, chạy `[1]` lần nữa với tên khác và đăng nhập
tài khoản đó trong browser. Script không đọc login của Codex App/CLI toàn cục,
không tìm `C:\Users\...\.codex`, không dùng `PATH`; nó gọi đúng binary cục bộ
chỉ với lệnh `login`, stage auth cục bộ cho native CCR import RPC rồi xóa
staging kể cả khi lỗi. Codex helper không bao giờ là coding harness.

Sau khi CCR nhập account, script không tin mù quáng model fallback của CCR.
Với account Free đã kiểm chứng ngày 2026-08-25, `gpt-5-codex` và
`gpt-5.6-sol` đều bị endpoint thật từ chối HTTP 400; `gpt-5.6-terra` và
`gpt-5.6-luna` hoàn tất stream nên được tạo thành hai route riêng. Generic
connection check của CCR đã báo Sol sai, vì vậy kết quả đường `/v1/messages`
thật được ưu tiên. Khi entitlement thay đổi, dùng `[R]` để kiểm tra lại.

Trong Claude, menu `/model` vẫn hiện các vai trò Opus/Sonnet/Haiku. Đó là ba
vai trò của harness Claude được ánh xạ vào route đã chọn, không phải ba model
Codex khác nhau. Model upstream thật được chọn ở menu `RUN_CLAUDE.bat`.

- Nếu chỉ có một model hợp lệ, script tạo một route.
- Nếu có nhiều model hợp lệ, mỗi model được tạo thành một route riêng.
- Nếu browser login đã thành công nhưng một bước sau đó lỗi, chạy lại `[1]` và
  nhập đúng cùng account label. Script tiếp tục local login dang dở mà không yêu
  cầu browser/2FA lần nữa, miễn phiên cục bộ còn dùng được.

Giới hạn quan trọng:

- Giao diện agent/profile của CCR bị vô hiệu hóa vì có thể sửa cấu hình ngoài
  folder; nó không phải màn hình nhập tài khoản Codex của wrapper.
- Nó không biến tài khoản ChatGPT Free hoặc Google website bất kỳ thành API.
- Codex import cần browser, mạng OpenAI và tài khoản có quyền dùng Codex.
- Password và mã 2FA chỉ nhập trên trang OpenAI; BAT/PowerShell không hỏi,
  không đọc và không lưu chúng.
- Browser login cho account-usage connector không đồng nghĩa với model API
  authorization; một số browser connector chỉ có trong CCR Desktop/Electron,
  còn project này chạy CCR CLI web management.

Route Codex do `SIGN_ACCOUNT.bat` tạo tự động nằm trong ignored
`.ccr-local/account-profiles.json`. Nếu tự quản lý một account provider khác
qua UI, vẫn có thể thêm profile vào `setting.json` với đúng tên provider:

```json
{
  "id": "imported-account",
  "name": "Imported account",
  "enabled": true,
  "provider": "EXACT CCR IMPORTED PROVIDER NAME",
  "model": "EXACT MODEL ID",
  "background_model": "EXACT MODEL ID",
  "think_model": "EXACT MODEL ID",
  "long_context_model": "EXACT MODEL ID"
}
```

Không thêm imported provider đó vào `providers` nếu muốn CCR UI tiếp tục sở
hữu credential của nó. Launcher sẽ giữ nguyên provider không có tiền tố
`local-setting--`.

## Menu RUN_CLAUDE.bat

- Số profile: chạy `bin/claude.exe` với route `Provider/model`.
- `[S]`: đọc lại và đồng bộ `setting.json` ngay trong cửa sổ đang mở.
- `[R]`: xác minh/trình bày trạng thái management và gateway.
- `[X]`: dừng CCR project-local.
- `[U]`: kiểm tra version/update, không tự merge hoặc thay binary.
- `[Q]`: thoát.

Không còn `[A]`, `[E]`, `[D]` hoặc prompt nhập API/client key.

## Tính độc lập và bí mật

- Claude: `bin/claude.exe`.
- Node: `provider_router/runtime/node.exe`.
- Codex login helper: `provider_router/codex-login-runtime/codex.exe`.
- CCR package: `provider_router/node_modules`.
- SQLite/account/provider state: `provider_router/.ccr-local`.
- Per-account login state:
  `provider_router/.ccr-local/codex-accounts/<account-id>`.
- API source file: ignored `setting.json`.
- Claude profile modes: `provider_router/.ccr-local/modes`.
- Generated CCR client key: ignored DPAPI ciphertext
  `provider_router/.ccr-local/router-client.dpapi`.

Project không được tạo/giữ CCR agent profile. Nếu takeover marker cục bộ xuất
hiện do một lần chạy thủ công, lần đồng bộ tiếp theo xóa profile và yêu cầu CCR
khôi phục cấu hình global từ backup của chính nó trước khi chạy Claude.

Không đưa `setting.json`, `.ccr-local`, screenshot có key, account export,
cookie, OAuth token hoặc request body lên Git/GitHub.

Binary login lớn được Git ignore; `provider_router/CODEX_LOGIN_SOURCE.json`
giữ version và SHA-256 để kiểm tra. Khi clone sang máy/folder mới và binary
không có, chủ động chạy `tools\install_codex_login_runtime.ps1`. Installer đặt
cả đích cài và state tạm trong dự án; normal startup không tự tải/cập nhật.

Tính độc lập này là độc lập filesystem/runtime: code không dựa vào hồ sơ Codex
toàn cục hay executable trên PATH. Browser và endpoint OpenAI/Google/DeepSeek
vẫn là dịch vụ mạng bên ngoài theo bản chất.

## Chạy song song và kiểm tra không tốn quota

Double-click `RUN_CLAUDE.bat` lần nữa mở terminal Claude khác; router background
được dùng chung. Từ terminal hiện có dùng `RUN_CLAUDE.bat --new-window`.

Các kiểm tra offline:

```text
RUN_CLAUDE.bat --version
RUN_CLAUDE.bat --router-version
python tools/verify_router_integration.py .
python tools/verify_setting_flow.py .
pwsh -File tools/router_project_menu.ps1 -Root . -SelfTest
```

Gate không đọc file thật sau khi bạn điền key và không gửi model request.
Connection check trong CCR UI hoặc khởi chạy profile là thao tác thật có thể
tiêu quota.
