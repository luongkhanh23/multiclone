# Hướng dẫn cập nhật phiên bản MultiClone

## 1. Đối với người dùng trên iPhone 11 (Sileo)
1. Mở **Sileo** → vào tab **Sources** → kéo xuống để làm mới kho MultiClone.
2. Khi có phiên bản mới, vào tab **Packages** → nhấn **Upgrade All** (hoặc chọn **MultiClone → Upgrade**).
3. Sau khi nâng cấp hoàn tất, nhấn **Restart SpringBoard**.
4. **Dữ liệu an toàn khi nâng cấp:** Script `Packaging/DEBIAN/postinst` chỉ khởi tạo cấu hình mặc định khi tệp preferences chưa tồn tại, vì vậy toàn bộ danh sách bản clone (`/var/mobile/Library/MultiClone/registry.json`), dữ liệu độc lập và cài đặt Auto Close của bạn được **giữ nguyên hoàn toàn**.

---

## 2. Đối với nhà phát triển khi phát hành bản mới
1. Tăng số phiên bản ở các vị trí sau:
   - `control` và `Packaging/control` (`Version: X.Y.Z`)
   - `Source/MultiCloneCore/MCConstants.m` (`MCProductVersion`)
   - `Manager/MultiCloneManager/Info.plist` (`CFBundleShortVersionString` và `CFBundleVersion`)
   - `Repository/depictions/com.multiclone.manager.json` (thêm mục changelog mới)
2. Chạy bộ kiểm thử tự động:
   ```bash
   python3 Tests/run_all_tests.py
   ```
3. Commit và tạo Git tag phát hành (ví dụ `v1.0.1`), rồi đẩy lên GitHub:
   ```bash
   git add .
   git commit -m "Bump version to 1.0.1"
   git tag v1.0.1
   git push origin main --tags
   ```
4. GitHub Actions (hoặc chạy cục bộ `./Scripts/build.sh && ./Scripts/build_repo.sh`) sẽ biên dịch `.deb` mới, kiểm tra cấu trúc rootless, tính SHA256 và cập nhật chỉ mục Sileo Repository tự động.
