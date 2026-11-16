# ERI Login Admin — iOS / Android Key Management

Repository **Menumod** chỉ dành cho hệ thống **ERI Login Key**. Giao diện quản trị là ứng dụng iPhone SwiftUI; không dùng web UI hay Python client.

## Mã nguồn hiện có
- apps/ERILoginAdmin/ERILoginAdminApp.swift — SwiftUI Admin iOS.
- project.yml — XcodeGen dành cho iOS 16+.
- .github/workflows/build-eri-login-admin.yml — GitHub Actions tạo IPA chưa ký.
- worker/src/index.js — API quản trị, xác minh và liên kết key với thiết bị.
- worker/migrations/0001_keys.sql — Cloudflare D1 database bền vững.
- worker/wrangler.toml.example — cấu hình ví dụ triển khai Worker/D1.

## Chức năng
Tạo key iOS/Android; xem danh sách; gia hạn ngày; khóa/mở khóa; gỡ liên kết thiết bị; xóa; kiểm tra API. Admin key được lưu trong iOS Keychain. Người dùng chỉ cần key thiết bị, không cần tài khoản/mật khẩu.

## Triển khai API
Trong thư mục worker, tạo database bằng npx wrangler d1 create ERI_KEYS, sao chép wrangler.toml.example thành wrangler.toml và điền database_id. Khai báo hai secret bằng npx wrangler secret put ADMIN_KEY và npx wrangler secret put DEVICE_PEPPER. ADMIN_KEY cần ít nhất 32 ký tự.
Chạy npx wrangler d1 migrations apply ERI_KEYS --remote, sau đó npx wrangler deploy. Trong Admin nhập URL HTTPS Worker và ERI_ADMIN_KEY, bấm lưu và kiểm tra.

API phía client: POST /api/verify với JSON gồm platform (ios/android), key và device_id; server trả ok và expires_at khi key còn hiệu lực. Dylib / .so phía client CHƯA được tạo trong repo này. Device ID do client gửi có thể bị giả mạo; cần cơ chế chứng thực thiết bị và chống lạm dụng/rate limiting trước khi dùng thương mại.

## Build
Workflow Build ERI Login Admin iOS IPA tạo artifact ERILoginAdmin-unsigned.ipa trên macOS, cần ký với chứng chỉ iOS và mobileprovision hợp lệ. Không có sẵn backend được triển khai hoặc bản đã kiểm thử trên iPhone.

## Mã cũ và menu
Phiên bản cũ của nhánh main (ERIHost, WebView, công cụ IPA/FPS) được sao lưu ở nhánh backup-main-before-login-cleanup-20261117. Không khôi phục các công cụ đó vì không thuộc login key.
Menu ImGui được chuyển sang repository boyngheoanvat-ctrl/zsp: https://github.com/boyngheoanvat-ctrl/zsp

**Trạng thái: Đây là mã nguồn ERI Login Admin được dựng mới, không phải bản IPA cũ được khôi phục.**