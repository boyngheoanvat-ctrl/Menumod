# Patch FPS 60/90 vào bản IPA Liên Quân đã cung cấp

**Trạng thái:** đã chạy công cụ patch tĩnh trên bản gốc trong phiên làm việc 2026-11-13, kiểm tra ZIP, xác nhận 784 entry không thay đổi danh sách và chỉ có 16 byte khác trong `UnityFramework`.

**Cần phân biệt:** Đây là sửa giá trị trả về cho `GameSettings.get_Supported60FPSMode` và `GameSettings.get_Supported90FPSMode` của build 1.64.11768577, không phải menu bật/tắt trong game và không bảo đảm thiết bị thực sự chạy 60/90 FPS.

## Tự tạo lại IPA đã sửa

Cung cấp **bản IPA gốc của bạn**. Không tải game từ repository này (repo không chứa IPA bên thứ ba).

```bash
python3 scripts/patch_ipa_fps.py \
  --ipa original.ipa \
  --fps 60,90 \
  --output ERI_LienQuan_FPS60_90_UNSIGNED.ipa
```

Công cụ từ chối mọi binary không trùng SHA-256 gốc đã kiểm tra và xác minh 8 byte lệnh trước khi ghi. Sửa ở RVA `0x55624B8` và `0x554C8BC`.

Để hoàn tác patch 60/90 trên bản IPA đã sửa:

```bash
python3 scripts/patch_ipa_fps.py \
  --ipa ERI_LienQuan_FPS60_90_UNSIGNED.ipa \
  --restore --fps 60,90 \
  --output restored_unsigned.ipa
```

**Ký ứng dụng:** Chữ ký cũ mất hiệu lực ngay khi sửa một byte trong binary. Phải ký lại mã thực thi và toàn bộ thành phần cần thiết bằng hồ sơ hợp lệ. Ký thành công cũng không đảm bảo game cho phép chạy bản đã sửa.

**Không được hiểu sai:** `ERIHost` trong repo là ứng dụng độc lập với WebView, **chưa nhúng vào tiến trình Liên Quân**. Công cụ này không can thiệp chống gian lận, báo cáo vi phạm, hệ thống mạng, hay hồ sơ người chơi. IPA được build từ `ERIHost` là ứng dụng khác, không phải Liên Quân đã mod.
