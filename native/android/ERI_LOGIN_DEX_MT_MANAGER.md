# ERI LOGIN Android — DEX + native .so

Đây là bộ mã nguồn ví dụ để thêm màn hình nhập key vào **ứng dụng Android mà bạn sở hữu hoặc có quyền chỉnh sửa**. Không có bước bypass kiểm tra chữ ký/chống can thiệp của game khác.

## File cần có

- `releases/ERI_LOGIN_classes.dex` — Activity Java đã biên dịch bằng d8 (mặc định DEX chứa class `com.eri.login.ERILoginActivity`)
- `native/android/arm64-v8a/libERILogin.so` — thư viện JNI Android ARM64
- `native/android/armeabi-v7a/libERILogin.so` — thư viện JNI Android ARM32
- `native/android/java/com/eri/login/ERILoginActivity.java` — mã nguồn Activity để biên dịch lại

## Cách đặt file

1. Chọn APK mà bạn được phép sửa và sao lưu nguyên bản trước.
2. Trong APK có nhiều DEX, đặt nội dung `ERI_LOGIN_classes.dex` thành **tên DEX tiếp theo chưa sử dụng**: ví dụ nếu có `classes.dex`, `classes2.dex`, `classes3.dex` thì đặt thêm `classes4.dex`. Không ghi đè bất kỳ DEX gốc nào.
3. Gắn đúng `libERILogin.so` vào `lib/arm64-v8a/` (ARM64), hoặc `lib/armeabi-v7a/` (ARM32). Đừng thay thế `libil2cpp.so`, `libunity.so` hoặc các thư viện game gốc.
4. Thêm `activity` bên dưới vào trong `<application>` của `AndroidManifest.xml`, và chuyển **chỉ** intent-filter `MAIN` + `LAUNCHER` từ Activity khởi động gốc sang Login. **Giữ nguyên** các intent-filter deep-link/BROWSABLE khác của app gốc.

Ví dụ cho tên Activity gốc `com.garena.game.kgtw.SGameActivity` đã quan sát trong file Manifest được cung cấp. Tên phải điều chỉnh cho ứng dụng của bạn:

```xml
<!-- Đặt bên trong <application>, không thay cả manifest -->
<meta-data
    android:name="eri.login.next_activity"
    android:value="com.garena.game.kgtw.SGameActivity" />

<activity
    android:name="com.eri.login.ERILoginActivity"
    android:exported="true"
    android:theme="@android:style/Theme.Material.NoActionBar">
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
        <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
    </intent-filter>
</activity>
```

Nếu bạn gỡ bộ lọc `MAIN/LAUNCHER` khỏi Activity gốc, phải giữ nguyên các thuộc tính, filter khác và metadata của Activity đó. **Không xóa Activity gốc.**

## Quy trình

- Android mở `com.eri.login.ERILoginActivity`.
- Activity nạp `System.loadLibrary("ERILogin")` rồi gọi JNI `nativeCheck(appId,key,deviceId,activate)`.
- `nativeCheck` trong `.so` gọi `eri_login_check` qua HTTPS, nhận kết quả từ máy chủ.
- Key hợp lệ: app mở Activity gốc khai báo bằng meta-data `eri.login.next_activity`.
- Key sai/không có Internet: giữ màn hình Login, hiển thị thông báo.

Để cấp key Android, dùng ERI LOGIN ADMIN.ipa và nhập đúng Android Package ID (`getPackageName()` trên app khách). Không đưa `ERI_ADMIN_KEY` vào APK.

## Giới hạn

- Chỉ việc thêm `.so` không tự mở Login. Phải có DEX, cấu hình Manifest và ứng dụng phải tải DEX.
- Không thể bảo đảm hoạt động trên APK có chống can thiệp hoặc kiểm tra chữ ký, và không hỗ trợ phá cơ chế đó.
- Đổi/sửa APK làm thay đổi chữ ký; app có thể không chạy nếu dựa vào chứng chỉ gốc.
- Launcher gate đơn thuần không phải giải pháp khóa gameplay chống bypass; các Activity/entrypoint khác vẫn có thể được gọi.
- Chưa có kết quả kiểm thử trên điện thoại thực tế. Nếu văng, lấy `logcat -b crash -d` để chẩn đoán.
