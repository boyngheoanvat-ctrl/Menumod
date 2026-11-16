# Menumod — ERI LOGIN ADMIN (khôi phục từ bản build gốc)

Kho mã của ứng dụng **ERI LOGIN ADMIN** quản lý key thiết bị cho iOS IPA và Android APK. Đây là **mã nguồn gốc** tại commit `b36dee13e20f9d2a00f0a22ad1db8b9f83fe8dbc`, tương ứng [Actions run #43604903103](https://github.com/boyngheoanvat-ctrl/Menumod/actions/runs/43604903103) ngày 14/11/2026. Các file không liên quan (ERIHost/WebView, công cụ IPA/FPS, ImGui) không được khôi phục.

## Thành phần

- `ios/ERILoginAdmin/ERILoginAdminApp.swift` — SwiftUI Admin gốc, không có form tài khoản/mật khẩu người dùng.
- `ios/ERILoginAdmin/Info.plist` — thông tin app/bundle ID gốc.
- `docs/ERI_LOGIN_ADMIN_HUONG_DAN.md` — hướng dẫn gốc, quản lý và kiểm thử key.
- `.github/workflows/build-login-admin.yml` — workflow từ bản gốc, chỉnh nhánh chạy thành `main` và bỏ bước tự ghi IPA trở lại repository để tránh làm rối mã nguồn.
- `releases/ERI_LOGIN_ADMIN_unsigned.ipa` — bản IPA chưa ký đã lưu trong git tại đúng commit nguồn; để lấy artifact **của run #43604903103**, mở trang Actions phía trên và tải artifact từ run đó.

## Chức năng

Tạo key, xem danh sách, gia hạn, khóa/mở khóa, reset liên kết thiết bị, xóa key. Admin Key được lưu iOS Keychain sau khi xác thực. Hỗ trợ App ID cho cả ứng dụng iOS/Android.

## Cấu hình

Ứng dụng gốc gọi tới `https://eri-login-api.onrender.com`; không tự động thay máy chủ hoặc dữ liệu hiện tại. Mã nguồn có thể build ra IPA chưa ký qua Actions, nhưng cần ký lại bằng chứng chỉ/hồ sơ iOS hợp lệ để cài lên iPhone. Chưa xác minh máy chủ Render còn hoạt động và chưa thử IPA trên máy thật.

## Sao lưu

- Bản `main` trước khi khôi phục: [backup-new-admin-before-original-restore-20261117](../../tree/backup-new-admin-before-original-restore-20261117)
- Mã kho trước khi dọn công cụ: [backup-main-before-login-cleanup-20261117](../../tree/backup-main-before-login-cleanup-20261117)
- Menu ImGui nằm riêng tại [zsp](https://github.com/boyngheoanvat-ctrl/zsp).
