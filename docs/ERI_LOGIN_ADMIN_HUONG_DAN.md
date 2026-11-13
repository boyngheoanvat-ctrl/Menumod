# HƯỚNG DẪN ERI LOGIN ADMIN + GẮN LOGIN VÀO IPA/APK

Repository: `boyngheoanvat-ctrl/Menumod`, branch `eri-login-admin`.

## 1. Cài ERI LOGIN ADMIN trên iPhone

- Tải `releases/ERI_LOGIN_ADMIN_unsigned.ipa` (IPA ARM64 iOS 16+).
- IPA chưa ký: ký với chứng chỉ `.p12` và `.mobileprovision` hợp lệ bằng công cụ ký iOS bạn đang dùng; sau đó mới cài được.
- Mở app, nhập ERI_ADMIN_KEY (bí mật của người quản trị) và bấm "Lưu khóa Admin trong Keychain".
- Điền App ID. App ID phải khớp chính xác với Bundle ID của IPA hoặc Android package name của APK sẽ yêu cầu Login.

## 2. Tạo tài khoản + mật khẩu

- Chọn tab `TK / Mật khẩu`.
- Nhập tên tài khoản, mật khẩu ít nhất 8 ký tự, thời hạn (số ngày 1–3650).
- Nhấn `Tạo TK + MK`. Có nút sao chép để giao thông tin cho khách.
- Nhấn `Tải danh sách TK` để xem các tài khoản. Có thể gia hạn, khóa/mở khóa, xóa.
- API hiện lưu mật khẩu ở dạng băm; không thể xem lại mật khẩu đã tạo.
- **Quan trọng:** Đây là hệ thống tài khoản/mật khẩu độc lập. Thư viện ERILogin.dylib và ERIAndroidGate.dex **chỉ hỗ trợ nhập key**, KHÔNG dùng tài khoản/mật khẩu. Không được quảng cáo rằng TK/MK đã hoạt động trong game khi chưa tích hợp thêm client tương ứng.

## 3. Tạo và quản lý key — 1 key / 1 thiết bị

- Chọn tab `Key 1 thiết bị`.
- Nhập tên người mua, số ngày và nhấn `Tạo key mới`.
- Sao chép và giao key một lần cho khách.
- Nhấn `Tải danh sách key` để xem trạng thái; có thể gia hạn, khóa/mở khóa, reset thiết bị hoặc xóa.
- Khi khách kích hoạt lần đầu, API sẽ liên kết key với UUID mà ứng dụng đã lưu trong Keychain (iOS) hoặc lưu trữ ứng dụng trên Android. Điều này **không phải chứng thực phần cứng tuyệt đối**.

## 4. Gắn ERI LOGIN vào IPA bằng Python trên iPhone

Cần dùng với ứng dụng mà bạn có quyền chỉnh sửa và phân phối.

1. Tải 2 file `injector/LOGIN.py` và `injector/ERILogin.dylib`.
2. Trong Documents của ứng dụng chạy Python, đặt `LOGIN.py`, `ERILogin.dylib` và **một** IPA mục tiêu vào cùng một thư mục.
3. Mở `LOGIN.py` và chạy. Python tự tìm IPA/APK gần nhất trong thư mục chứa script; nên chỉ đặt 1 file mục tiêu để tránh chọn nhầm.
4. Nếu Mach-O ARM64 64-bit là dạng thin, không bị FairPlay mã hóa và còn vùng trống cho lệnh nạp dylib, Python chèn `LC_LOAD_DYLIB`, đưa `ERILogin.dylib` vào Frameworks và xuất `<ten>_ERI_LOGIN_unsigned.ipa`.
5. Ký lại **cả ứng dụng và dylib** bằng chứng chỉ/hồ sơ hợp lệ, sau đó mới thử cài trên iPhone.

**Giới hạn:** Python báo lỗi nếu IPA không tương thích; không tự động build dylib trên iPhone vì dylib đã build sẵn. Việc chèn load command không chứng minh màn hình Login thực sự chặn game. Unity, app có kiểm tra chữ ký, anti-tamper hoặc nhiều launcher có thể cần tích hợp mã nguồn để khóa game đúng cách. Không dùng bản chưa kiểm thử để bán.

## 5. Với APK Android

- Dùng `injector/LOGIN.py` và `injector/ERIAndroidGate.dex` cạnh APK, chạy trong hệ thống có Java, apktool và Android SDK (zipalign, apksigner, keytool).
- Python sẽ kiểm tra manifest, thay launcher khi tương thích, đóng gói DEX rồi ký APK nếu có đủ công cụ.
- Không thể làm đầy đủ bước APK từ Python iPhone thông thường nếu thiếu apktool và Android SDK.
- APK ký bằng khóa khác thường không cập nhật đè lên APK cũ.

## 6. Máy chủ

- API hiện tại: `https://eri-login-api.onrender.com`.
- Thiết bị khách KHÔNG được nhận ERI_ADMIN_KEY. Key Admin chỉ nhập trong ERI LOGIN ADMIN.
- **Hạ tầng API hiện vẫn triển khai từ nhánh riêng `eri-login-render` trên EriMail.** Mã nguồn ứng dụng Admin và bộ công cụ được lưu trong Menumod. Việc chuyển API sang repo Menumod cần thay liên kết triển khai Render một cách an toàn, không xóa nhánh đang phục vụ khách.

## 7. Xác thực build

- Xem workflow `Build Menumod ERI Login Admin IPA` trên GitHub Actions.
- Trình build kiểm tra parse và biên dịch Swift ARM64, `unzip -t` IPA.
- Việc build thành công không thay thế kiểm thử API, tạo key, cài và mở IPA thực tế trên thiết bị.
