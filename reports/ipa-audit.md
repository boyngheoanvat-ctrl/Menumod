# Kiểm tra tĩnh IPA và dump(5).txt

Ngày kiểm tra: 2026-11-13. Đây là báo cáo đọc dữ liệu, **không phải bản mod game hoàn chỉnh**.

## IPA được cung cấp

- Bundle ID: `com.garena.game.kgvn`
- Version: `1.64.11768577`
- Build: `1.64.1.1768577`
- `UnityFramework`: 240.887.264 byte; Mach-O ARM64; `cryptid=0`
- Có lệnh chữ ký mã Mach-O và thư mục `_CodeSignature`. Không có `embedded.mobileprovision` ở vị trí mặc định.
- Thư mục ứng dụng gốc gồm `kgvn`, `UnityFramework` và các framework bổ trợ. Loại bỏ mã thực thi gốc sẽ khiến trò chơi ngừng hoạt động.

## Dump(5).txt

Các class/method phục vụ phân tích phần hiển thị, không phải API công khai:

| Class | Khai báo nhìn thấy |
|---|---|
| `GameSettings` | `get_Supported60FPSMode`, `get_Supported120FPSMode`, `DowngradeFpsLinkedQuality` |
| `CameraSystem` | `GetZoomRate` |
| `Moba_Camera` | `get_currentZoomAmount` |
| `MaskBlur` | `SetQuality` |

Các RVA khai báo trong dump nằm trong khoảng địa chỉ mã `__TEXT` của binary. **Chỉ kiểm tra phạm vi địa chỉ, chưa xác nhận các byte lệnh có khớp.**

## Chưa hoàn thành

- Chưa có menu được nhúng và chạy trong tiến trình Liên Quân.
- Chưa có patch game được kiểm chứng trên thiết bị.
- Không thể tự tạo API nội bộ Unity chỉ bằng WebView.
- IPA chưa được chỉnh sửa, build lại hay ký cài đặt được.
- Dự án ERI Host hiện là ứng dụng riêng. Đầu ra unsigned (nếu build) cần ký trước khi cài lên iPhone.

## Công cụ kiểm tra

```bash
python3 scripts/audit_game_archive.py \
  --ipa "/path/to/com.garena.game.kgvn.ipa" \
  --dump "/path/to/dump(5).txt" \
  --output "audit.json"
```

Bộ kiểm tra không sửa file IPA, không áp dụng patch, không truy cập bộ nhớ hoặc chống gian lận.
