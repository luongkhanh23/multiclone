# Hướng dẫn tạo Sileo Repository miễn phí trên GitHub Pages

MultiClone đã chuẩn bị sẵn toàn bộ cấu trúc kho lưu trữ Sileo hợp lệ tại thư mục `Repository/` và workflow tự động build `.deb` + cập nhật chỉ mục tại `.github/workflows/build-and-publish.yml`. **Không có URL giả nào được nhúng sẵn** — trang `Repository/index.html` tự động nhận diện URL thật của bạn khi chạy trên GitHub Pages.

---

## Bước 1: Tạo GitHub Repository mới
1. Đăng nhập tài khoản GitHub của bạn và tạo một repository mới (nên để chế độ **Public** để GitHub Pages và GitHub Actions macOS runner miễn phí).
2. Đưa thư mục `MultiClone/` lên GitHub:
   ```bash
   cd "C:\Users\luong\Downloads\app clone\MultiClone"
   git init -b main
   git add .
   git commit -m "Release MultiClone v1.0.0 for iOS 18.2 Dopamine Rootless"
   git remote add origin https://github.com/<TEN_TAI_KHOAN>/<TEN_REPO>.git
   git push -u origin main
   ```

## Bước 2: Bật GitHub Pages bằng GitHub Actions
1. Trên trang GitHub repository → vào **Settings** → **Pages**.
2. Ở mục **Build and deployment → Source**, chọn **GitHub Actions**.
3. Chuyển sang tab **Actions** → workflow **`Build MultiClone Rootless DEB & Publish Sileo Repo`** sẽ tự động chạy trên `macos-15`:
   - Cài Theos, `ldid`, `dpkg` và lấy **iOS SDK thật từ Xcode**.
   - Chạy bộ kiểm thử tự động `Tests/run_all_tests.py`.
   - Biên dịch thực tế `MultiClone.deb` (`arm64` + `arm64e`, rootless).
   - Kiểm tra cấu trúc rootless qua `Scripts/verify_package.sh` và tính `SHA256SUMS.txt`.
   - Chạy `Scripts/build_repo.py` tạo `Packages`, `Packages.gz`, `Packages.bz2`, `Release`.
   - Tự động xuất bản thư mục `Repository/` lên GitHub Pages (HTTPS).

## Bước 3: Thêm kho vào Sileo trên iPhone 11
1. Mở URL GitHub Pages vừa được triển khai trên Safari của iPhone 11 (hiển thị ngay trong job `deploy-sileo-pages` của GitHub Actions).
2. Nhấn nút **Thêm nguồn này vào Sileo** (hoặc sao chép URL dán vào **Sileo → Sources → `+`**).
3. Tải `MultiClone.deb` kèm `SHA256SUMS.txt` và `build.log` từ mục **Artifacts** của lần chạy Actions nếu muốn lưu trữ hoặc kiểm tra thủ công.

---

## Cập nhật chỉ mục Repo thủ công trên máy cục bộ (macOS / Linux / Windows)
Khi bạn đặt tệp `.deb` đã biên dịch thật vào `Releases/`, chạy:
```bash
python3 Scripts/build_repo.py Releases Repository
```
Lệnh sẽ tự động sao chép `.deb` vào `Repository/debs/`, trích xuất `DEBIAN/control`, tính `MD5sum`, `SHA1`, `SHA256`, tạo lại `Packages`, `Packages.gz`, `Packages.bz2` và `Release`.
