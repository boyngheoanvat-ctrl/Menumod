# ERI LOGIN — MOD BY ERI NGUYỄN

Phiên bản mới của nhánh `eri-login-admin` trong repository `boyngheoanvat-ctrl/Menumod`.

## Chỉ dùng KEY / 1 thiết bị

**Không còn giao diện tạo tài khoản/mật khẩu (TK/MK) trong IPA Admin.**
**Không còn form TK/MK trong ERI LOGIN dành cho khách.**

- Khách nhập key được Admin cấp, đúng dạng `ERI-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`.
- Ví dụ tên `EriNguyen` KHÔNG phải key hợp lệ.
- Key có hạn dùng, có thể khóa, mở khóa, gia hạn hoặc xóa.
- Khi key được kích hoạt lần đầu, máy chủ lưu liên kết với định danh ứng dụng của thiết bị đó. Một key chỉ dùng được với một định danh thiết bị tại một thời điểm.
- Reset thiết bị bằng IPA Admin cho phép khách kích hoạt lại sau khi đổi máy.
- Quy tắc thiết bị này không phải xác thực phần cứng bất biến.

## Tải ERI LOGIN ADMIN IPA

File: `releases/ERI_LOGIN_ADMIN_unsigned.ipa`

Ứng dụng quản lý **key thiết bị** (không còn tạo TK/MK):

1. Ký IPA bằng chứng chỉ iOS hợp lệ, sau đó cài lên iPhone.
2. Nhập `ERI_ADMIN_KEY` trên iPhone một lần và bấm **XÁC THỰC & ĐỒNG BỘ**.
3. Ứng dụng lưu khóa Admin trong Keychain sau khi máy chủ chấp nhận. Không cần nhập lại khi mở app thông thường.
4. Cấu hình `App ID` trùng chính xác với bundle ID/package name của ứng dụng sẽ kiểm tra key.
5. Nhập tên khách và số ngày, bấm **TẠO KEY MỚI**.
6. Sao chép key mới để giao khách. Key đầy đủ chỉ hiển thị sau khi tạo.
7. Trong danh sách có **gia hạn, khóa/mở khóa, reset máy, xóa key**.

Không nhúng `ERI_ADMIN_KEY` trong game hoặc thư viện dùng cho khách.

## iOS: ERILogin.dylib

- Mã nguồn: `native/ios/ERILogin.m`.
- Thư viện đã build: `native/ios/ERILogin.dylib`.
- Giao diện tối: **MOD BY ERI NGUYỄN**, biểu tượng khóa, nút dán key, nút kích hoạt với nền chuyển sắc.
- Đăng nhập bằng **key duy nhất**, không có lựa chọn TK/MK.
- Chỉ dùng trong ứng dụng iOS mà bạn sở hữu hoặc có quyền sửa; liên kết dylib vào target, nhúng đúng install name `@executable_path/Frameworks/ERILogin.dylib`, ký ứng dụng và dylib.

**Không thể chỉ chép dylib vào IPA bất kỳ mà tự có Login.** Ứng dụng phải nạp dylib. Overlay Login không chứng minh mọi luồng gameplay đã bị chặn trước khi xác thực.

## Android: libERILogin.so

- ARM64: `native/android/arm64-v8a/libERILogin.so`.
- ARM32: `native/android/armeabi-v7a/libERILogin.so`.
- Tích hợp dự án Unity qua `native/unity/ERILoginBootstrap.cs`, đặt trong scene BootLogin ở đầu Build Settings, cấu hình scene game kế tiếp.
- `libERILogin.so` xác minh key qua API HTTPS. Unity chỉ tải scene game sau khi key hợp lệ.
- Chỉ build APK/AAB qua dự án Unity có mã nguồn và quyền chỉnh sửa.

## Máy chủ

API: `https://eri-login-api.onrender.com`.

Máy chủ vẫn có đường dẫn tài khoản cũ cho tương thích với hệ thống trước đây, nhưng **giao diện Admin và Login mới không dùng TK/MK**. Không tự động xóa tài khoản/dữ liệu cũ trên server khi bỏ chức năng khỏi giao diện.

## Kiểm chứng

- Build IPA Admin và dylib iOS bằng GitHub Actions.
- Build .so Android bằng Android NDK.
- Sau khi ký và cài, kiểm thử trên thiết bị thật: key mới, key hết hạn, key khóa, dùng key trên thiết bị thứ hai, và reset thiết bị.
- Thành công khi biên dịch không tự chứng minh thư viện đã được nạp vào game của bên thứ ba.
