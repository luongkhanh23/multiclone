# Trạng thái Build thực tế (`Releases/`)

## Hiện trạng môi trường cục bộ
- **Hệ điều hành chạy phiên phát triển:** Windows (chưa cài WSL distro, Docker, Theos, clang iOS toolchain, iOS SDK, `ldid`, `dpkg-deb`).
- **Quyết định kỹ thuật:** Tuân thủ nghiêm ngặt yêu cầu **không tạo file `MultiClone.deb` giả và không tuyên bố build thành công khi chưa biên dịch thực tế**.

## Cách tạo sản phẩm `MultiClone.deb` thực tế (arm64 + arm64e, Rootless)

### Phương án A — GitHub Actions (`macos-15` với Xcode & iOS SDK thật)
1. Push thư mục `MultiClone` lên GitHub repository của bạn (xem [Documentation/GITHUB_PAGES_SILEO.md](../Documentation/GITHUB_PAGES_SILEO.md)).
2. Workflow `.github/workflows/build-and-publish.yml` tự động biên dịch và xuất các tệp thật:
   - `Releases/MultiClone.deb`
   - `Releases/SHA256SUMS.txt`
   - `Releases/build.log`
   - Đồng thời cập nhật `Repository/` lên GitHub Pages để thêm trực tiếp vào Sileo.

### Phương án B — Biên dịch trên macOS / Linux / WSL2 (Ubuntu)
```bash
cd MultiClone
./Scripts/setup_theos.sh
export THEOS="$HOME/theos"
./Scripts/build.sh
./Scripts/build_repo.sh ./Releases ./Repository
```
Sau khi chạy thành công, `Releases/` sẽ chứa:
- `MultiClone.deb` (đã xác minh cấu trúc rootless qua `Scripts/verify_package.sh`)
- `SHA256SUMS.txt`
- `build.log`
