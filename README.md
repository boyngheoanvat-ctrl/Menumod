# ERI Native Host + WebView API

Dự án iOS **độc lập** gồm giao diện web và một cầu nối JavaScript ↔ Swift native. Cầu nối chỉ điều khiển các chức năng của chính ứng dụng ERI Host, không kết nối và không can thiệp IPA Liên Quân/Garena.

## Tình trạng

- ✅ Mã nguồn Swift của host ứng dụng iOS.
- ✅ WebView tải giao diện `Web/index.html` được nhúng trong ứng dụng.
- ✅ API hai chiều với ID yêu cầu và phản hồi kết quả thực từ Swift.
- ✅ API `ping`, `getState`, `setFeature`, `reset`.
- ✅ Native state và lưu `UserDefaults` cho ba chức năng demo: `overlay`, `darkCanvas`, `haptics`.
- ✅ Trang `Web/index.html` có thể xem trên trình duyệt. Khi chạy ngoài ERI Host, nó thông báo **không có native bridge** thay vì giả báo bật thành công.
- ✅ GitHub Actions build iOS Simulator và tạo gói IPA iOS ARM64 **chưa ký**, workflow kiểm tra web.
- ✅ Công cụ kiểm tra tĩnh IPA + dump (không patch), xem `scripts/audit_game_archive.py` và `reports/ipa-audit.md`.
- ❌ Không có tích hợp với tiến trình game, thay đổi bộ nhớ Unity, anti-cheat bypass, hay chỉnh sửa IPA gốc.
- ❌ Chưa có IPA cài đặt được trên iPhone: phải build và ký app với chứng chỉ/hồ sơ phù hợp.

## Tại sao không xoá native cũ của IPA Liên Quân?

`kgvn`, `UnityFramework` và các framework trong IPA là thành phần chạy game. Xoá chúng rồi thay bằng một WebView hoặc API không còn là game. Không có mã nguồn gốc để xây lại toàn bộ game; dự án này **không ghi đè hoặc xoá** bất kỳ thành phần nào trong IPA đã cung cấp.

## Build

Trên macOS với Xcode, cài [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project ERIHost.xcodeproj -scheme ERIHost -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Muốn cài trên iPhone thật cần mở project trong Xcode, chọn Team ký và build cho thiết bị. GitHub Actions tạo bản iOS Simulator và file `ERIHost-iOS-arm64-unsigned.ipa` cho thiết bị, nhưng **IPA này chưa ký, không cài trực tiếp được**; cũng không chứa game Liên Quân.

## API protocol v1

Giao diện gửi object vào `window.webkit.messageHandlers.eri.postMessage(...)`:

```json
{"id":"req-1","type":"setFeature","feature":"overlay","enabled":true}
```

Swift gửi trả về callback `window.__eriReceive(response)`:

```json
{"id":"req-1","ok":true,"payload":{"features":{"overlay":true,"darkCanvas":false,"haptics":true},"host":"ERIHost","thirdPartyGameConnected":false}}
```

- `ping` kiểm tra bridge; `getState` đọc trạng thái.
- `setFeature` chỉ chấp nhận `overlay`, `darkCanvas`, `haptics` và boolean `enabled`.
- `reset` đặt lại trạng thái mặc định.
- Tham số không hợp lệ nhận `ok:false` và `error`, không có hiệu ứng giả.
- `thirdPartyGameConnected` luôn là `false`, vì ứng dụng này không tích hợp vào game của bên thứ ba.

## Phân phối website

`Web/index.html` chạy độc lập (chỉ xem giao diện) và có thể triển khai bằng GitHub Pages từ thư mục `Web`. Để dùng Native API cần mở website **bên trong ERI Host**; Safari không có cầu nối riêng này.

## Kiến trúc

```text
Web/index.html
    │ window.webkit.messageHandlers.eri.postMessage()
    ▼
ERIHost/HostApp.swift
    │ kiểm tra lệnh, whitelist và cập nhật trạng thái
    ▼
UIKit + UserDefaults
    │
    └─ window.__eriReceive(response)
```

Dự án này không phân phối mã nhị phân Garena, không xoá/bỏ qua lớp bảo mật game và không đưa tuyên bố kết nối API chính thức khi không có.
