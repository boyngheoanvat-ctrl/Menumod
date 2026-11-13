# ERI LOGIN — Native iOS dylib / Android .so + ERI ADMIN IPA

Repository: `boyngheoanvat-ctrl/Menumod`, branch `eri-login-admin`.

## Thành phần chính

- `native/ios/ERILogin.dylib`: thư viện ARM64 iOS, màn hình nhập key và kiểm tra API (đã build bằng iOS SDK).
- `native/android/arm64-v8a/libERILogin.so`: thư viện Android ARM64, xác thực key online qua Android HTTPS (JNI).
- `native/android/armeabi-v7a/libERILogin.so`: thư viện Android ARM32.
- `native/unity/ERILoginBootstrap.cs`: mã gọi native `.so` trong **dự án Unity được quyền chỉnh sửa**; giữ game trong boot scene cho đến khi key hợp lệ.
- `releases/ERI_LOGIN_ADMIN_unsigned.ipa`: IPA quản trị (chưa ký) để tạo tài khoản/mật khẩu, cấp key, gia hạn, khóa/mở khóa, reset thiết bị, xóa.

**Không dùng Python hoặc Android DEX để sửa IPA/APK.** Không có trình chèn tự động vào game đã biên dịch.

## ERI LOGIN ADMIN IPA — tạo tài khoản / mật khẩu và key

1. Tải `releases/ERI_LOGIN_ADMIN_unsigned.ipa` và ký ứng dụng bằng chứng chỉ iOS hợp lệ trước khi cài.
2. Mở IPA Admin, nhập `ERI_ADMIN_KEY` **chỉ một lần**, nhấn **Kiểm tra & Lưu khóa Admin**. Khi máy chủ phản hồi thành công, khóa được lưu vào Keychain và tự dùng lại khi mở app.
3. Điền App ID trùng chính xác với bundle identifier (iOS) hoặc package name (Android) của ứng dụng cần xác thực.
4. Tab **TK / Mật khẩu**: tạo tên tài khoản, mật khẩu >= 8 ký tự, thời hạn; xem danh sách và gia hạn/khóa/mở khóa/xóa.
5. Tab **Key 1 thiết bị**: cấp key, sao chép key sau khi tạo, xem trạng thái, gia hạn/khóa/mở khóa/xóa/reset thiết bị.

**Lưu ý**: Hiện thư viện native dùng **key**, không dùng TK/MK. Đây là hai phương thức khác nhau. Mật khẩu khách không đọc lại được từ máy chủ.

**Không bao giờ** nhúng `ERI_ADMIN_KEY` vào dylib hoặc .so phân phối cho khách. API: `https://eri-login-api.onrender.com`.

## Android: gắn trực tiếp `libERILogin.so` vào dự án Unity

Áp dụng cho **dự án Unity có mã nguồn** mà bạn có quyền chỉnh sửa.

1. Chép `native/android/arm64-v8a/libERILogin.so` vào `Assets/Plugins/Android/arm64-v8a/libERILogin.so`.
2. Nếu build Android ARM32, chép thêm `native/android/armeabi-v7a/libERILogin.so` vào thư mục tương ứng.
3. Chép `native/unity/ERILoginBootstrap.cs` vào `Assets/Scripts/`.
4. Tạo scene đầu tiên tên **BootLogin** chứa một GameObject với `ERILoginBootstrap`. Cấu hình trường `nextScene` thành scene game thực tế (được thêm vào Build Settings). **Không đặt gameplay vào BootLogin**.
5. Giữ quyền Android `INTERNET` trong manifest. Build APK/AAB bằng Unity. Unity load `.so` và màn hình BootLogin gọi hàm native `eri_login_check` để kích hoạt/xác thực key; chỉ chuyển vào game khi API trả `valid:true`.
6. Cài và thử trên thiết bị Android thật. Chữ ký APK khi build phải thuộc ứng dụng do bạn quản lý.

Android lưu ID UUID theo dữ liệu ứng dụng bằng PlayerPrefs, không phải chứng thực phần cứng bất biến. Hệ thống xác thực online; mất kết nối sẽ không mở scene game.

## iOS: gắn trực tiếp `ERILogin.dylib` vào ứng dụng bạn có thể build

1. Trong dự án iOS mà bạn sở hữu, liên kết dylib trong target và cấu hình **Embed & Sign** (hoặc đóng gói dylib trong `Frameworks` và bảo đảm lệnh nạp Mach-O hợp lệ).
2. Dylib hiện có install-name `@executable_path/Frameworks/ERILogin.dylib`, hiển thị cửa sổ nhập key khi được nạp.
3. Ký app và dylib bằng chứng chỉ/hồ sơ tương thích, build IPA qua Xcode, cài và kiểm tra trên iPhone.
4. Kiểm tra rằng ứng dụng chưa đi vào gameplay trước khi xác thực. Overlay chạy trong dylib không chứng minh mọi hoạt động nền của ứng dụng bị chặn; ứng dụng cần tích hợp gate tại khởi động nếu muốn kiểm soát hoàn toàn.

Với **IPA/APK đã biên dịch của bên thứ ba**, chỉ chép dylib/.so vào ZIP không làm nó tự nạp và không bảo đảm màn hình hiện lên. Muốn tích hợp chắc chắn phải có dự án nguồn hoặc hệ thống plugin/loader được ứng dụng hỗ trợ và quyền hợp lệ.

## Máy chủ

Render API: `https://eri-login-api.onrender.com`.

Máy chủ hiện vẫn được triển khai từ nhánh riêng `eri-login-render` trong EriMail. Điều đó **không làm thay đổi chức năng shop**, nhưng muốn tách hạ tầng hoàn toàn cần chuyển service Render sang mã backend thuộc Menumod theo một kế hoạch riêng, không xóa nhánh đang được dùng.

## Kiểm tra trước khi bán

- Xác nhận GitHub Actions build `.so` và IPA Admin thành công.
- Cài từng ứng dụng đã tích hợp lên thiết bị thực, thử key mới, key hết hạn, key bị khóa, và key trên thiết bị thứ hai.
- Xác nhận game không truy cập gameplay trước khi API xác thực.
- Không gọi một thư viện biên dịch thành công là IPA/APK đã gắn Login hoàn chỉnh.
