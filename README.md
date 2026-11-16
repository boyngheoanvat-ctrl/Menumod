# Menumod — ERI Login Key

Kho mã này được dành riêng cho dự án **ERI Login Key** (xác thực key theo thiết bị cho iOS/Android).

## Trạng thái mã nguồn
Nhánh `main` hiện chưa có mã triển khai login key. Các thành phần ERI Native Host/WebView, công cụ phân tích IPA và bản vá FPS không thuộc dự án login key đã được đưa ra khỏi `main`.

Để tránh mất dữ liệu, toàn bộ phiên bản cũ của `main` được lưu ở nhánh:
[`backup-main-before-login-cleanup-20261117`](../../tree/backup-main-before-login-cleanup-20261117).

## Phân chia dự án
- **Menumod:** Dành cho login key.
- **[zsp](https://github.com/boyngheoanvat-ctrl/zsp):** Dành cho menu Dear ImGui / dylib.

> Không có mã login key nào được tạo hay thay thế trong lần dọn kho này.
