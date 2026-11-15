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
4. Thêm Activity và meta-data trong Manifest. Chọn **một** trong hai cách mở màn hình: (A) Login là launcher, hoặc (B) gọi hàm `Start(Context)` từ Activity gốc bằng Smali. Không cần chuyển launcher nếu dùng cách (B).

### Cách A — ERI LOGIN làm launcher

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

### Cách B — Gọi Login qua Smali giống menu Start(Context)

Sau khi có DEX và .so, khai báo Activity (không thêm MAIN/LAUNCHER và không chuyển launcher gốc):

```xml
<!-- Đặt trong <application> -->
<meta-data android:name="eri.login.next_activity"
    android:value="com.garena.game.kgtw.SGameActivity" />

<activity android:name="com.eri.login.ERILoginActivity"
    android:exported="false"
    android:theme="@android:style/Theme.Material.NoActionBar" />
```

Nếu bạn đang chỉnh sửa `onCreate(Landroid/os/Bundle;)V` của một Activity và `p0` thực sự là Activity/Context, dùng sau `invoke-super`:

```smali
invoke-static {p0}, Lcom/eri/login/ERILoginActivity;->Start(Landroid/content/Context;)V
```

**Không** thay đường dẫn thành `Lcom/eri/vip/ERIVipActivity;` hoặc `Luk/lgl/MainActivity;`; phương thức này thuộc `Lcom/eri/login/ERILoginActivity;`. `Start` mở Login bằng `Intent` và yêu cầu Activity gọi nó `finish()`. Sau khi xác thực thành công, lớp Login mở lại Activity game gốc và dùng cờ nội bộ dùng một lần để tránh vòng lặp mở Login. Nếu `p0` không phải Context thì lệnh này sai và có thể gây lỗi xác minh DEX.

**Giới hạn**: một lệnh `invoke-static` kiểu `void` không dừng phần lệnh còn lại trong `onCreate`; Activity game có thể vẫn chạy tiếp công việc khởi tạo phía sau trước khi `finish()` có hiệu lực. Đây không phải cơ chế chặn toàn bộ gameplay chắc chắn. Muốn bảo đảm chỉ khởi chạy game sau khi xác thực, nên dùng cách A trong ứng dụng do bạn quản lý thay vì chỉ móc lệnh vào game đã biên dịch.

### Chặn khởi tạo Unity trước khi key hợp lệ

Với `com.unity3d.player.UnityPlayerActivity.onCreate(Bundle)` **trong dự án mà bạn được phép sửa**, bản DEX mới hỗ trợ phương thức `StartAndGate(Context)Z`. Sau khi gọi `invoke-super ... onCreate` và trước khi gọi `StartUnity()`, dùng:

```smali
invoke-static {p0}, Lcom/eri/login/ERILoginActivity;->StartAndGate(Landroid/content/Context;)Z
move-result v0
if-eqz v0, :eri_continue
return-void
:eri_continue
# Các lệnh khởi tạo game gốc và menu LGL đặt từ đây trở xuống.
```

`true` nghĩa là Login đang được mở hoặc không thể mở nên phải dừng `onCreate`. `false` chỉ khi Login đã xác thực key và mở lại Activity game trong cùng tiến trình. Không thêm dòng này vào trước `invoke-super onCreate`. Đừng gọi `Start(Context)V` và `StartAndGate(Context)Z` cùng lúc. Giữ nguyên `.registers` nếu v0 đã đủ và không làm thay đổi các thanh ghi tham số. Chỉ dùng một kiểu mở Login: launcher trong Manifest hoặc lệnh này.

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
