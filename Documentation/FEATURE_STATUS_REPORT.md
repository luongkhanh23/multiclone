# Báo cáo trạng thái hoàn thành & kiểm thử — MultiClone v1.0.0

## 1. Danh mục tính năng đã hoàn thành trong mã nguồn

| Nhóm chức năng | Module / File | Trạng thái | Ghi chú kỹ thuật |
|---|---|---|---|
| **Core & Rootless Path Helpers** | `Source/MultiCloneCore/MCConstants.*`, `MCModels.*` | Hoàn thành | Hỗ trợ `/var/jb`, kiểm tra Bundle ID, danh sách bảo vệ toàn bộ `com.apple.*` + công cụ jailbreak, kiểm soát phạm vi đường dẫn (`MCIsPathStrictlyInsideDirectory`). |
| **ZIP Engine chống Zip Slip** | `Source/MultiCloneCore/MCZipArchive.*` | Hoàn thành | Tự viết trên `libz` (`<zlib.h>`), không phụ thuộc thư viện ngoài; chặn hoàn toàn đường dẫn `..` hoặc tuyệt đối. |
| **Mach-O & DRM/Entitlement Parser** | `Source/MultiCloneCore/MCMachOInspector.*`, `Source/CLI/ipa_inspect.py` | Hoàn thành | Đọc trực tiếp Thin 64-bit & FAT Mach-O: kiến trúc `arm64`/`arm64e`, cờ mã hóa FairPlay DRM (`LC_ENCRYPTION_INFO_64`), trích xuất XML Entitlements từ `LC_CODE_SIGNATURE` SuperBlob (`0xfade7171`). |
| **IPAInspector & Compatibility Check** | `Source/IPAInspector/MCIPAInspector.*` | Hoàn thành | Phân tích `Info.plist`, icon, executable, Frameworks, Extensions (`.appex`), `embedded.mobileprovision`, URL Schemes; chặn DRM/kiến trúc sai; cảnh báo rõ App Groups, Keychain, Push, Associated Domains và app xác minh phía máy chủ (Facebook, Zalo, TikTok). |
| **CloneEngine giao dịch (Rollback)** | `Source/CloneEngine/MCCloneEngine.*` | Hoàn thành | Tạo Bundle ID duy nhất không giới hạn nhân tạo, giải nén vào `Staging/<uuid>`, sửa `Info.plist` & `.appex` trên bản sao, áp dụng icon, ký ad-hoc an toàn nếu có `ldid`, xuất `.ipa`, tự động hoàn tác sạch khi có lỗi. Không chạm ứng dụng gốc. |
| **DataManager & Storage Inspector** | `Source/DataManager/MCDataManager.*` | Hoàn thành | Registry JSON nguyên tử, tính dung lượng thực (`Bundle / Data / Cache`), xóa cache độc lập, đặt lại dữ liệu độc lập, xuất cấu hình JSON, khóa an toàn đường dẫn không cho xóa ngoài `MCManagedRootDirectory`. |
| **IconManager** | `Source/IconManager/MCIconManager.*` | Hoàn thành | Trích xuất icon từ IPA/app cài sẵn, resize PNG `@2x` (120×120) và `@3x` (180×180), lưu cache và cập nhật `CFBundleIcons` trong bản clone. |
| **Auto Close Previous App** | `Tweak/MultiCloneSpringBoard/*`, `Source/AutoClose/*`, `MCPrivateAPIBridge.*` | Hoàn thành | Nâng cấp từ v0.3: tương thích ngược khóa/notification cũ; bổ sung IPC 2 lớp (`CFPreferences` + atomic `ipc_state.plist`), xác nhận trước khi đóng, hành vi khởi chạy, phản hồi trạng thái lỗi (`ack`), Ping/Pong kiểm tra tweak, cô lập Private API (`FBSSystemService`, `LSApplicationWorkspace`) trong `@try/@catch` và kiểm tra kích thước tham số `NSMethodSignature`. |
| **MultiClone Manager (Dark Mode App)** | `Manager/MultiCloneManager/*` | Hoàn thành | Ứng dụng UIKit Dark Mode đủ 4 khu vực: Trang chủ (tìm kiếm, danh sách clone & app đã cài, trạng thái), Tạo Clone (chọn IPA, phân tích tự động, báo cáo tương thích, nhập tên/Bundle ID/icon, tiến trình), Quản lý Clone (mở/đổi tên/đổi icon/dung lượng/dữ liệu độc lập/chia sẻ IPA/xóa), Cài đặt (Auto Close, xác nhận, hành vi, giao diện Dark Mode, Ping SpringBoard, Nhật ký lỗi). |
| **Logger & Settings (Keychain)** | `Source/Logger/*`, `Source/Settings/*` | Hoàn thành | Xoay vòng log 512KB, tự động che giấu `token`/`password`/`secret`/`cookie`, lưu giá trị nhạy cảm bằng Keychain (`SecItem*`). |
| **Theos Rootless & DEBIAN Packaging** | `Makefile`, `control`, `Packaging/DEBIAN/*`, `Scripts/build.sh`, `Scripts/verify_package.sh` | Hoàn thành | Chuẩn `THEOS_PACKAGE_SCHEME=rootless`, `arm64 arm64e`, `iphoneos-arm64`, `postinst`/`prerm`/`postrm` hỗ trợ `uicache` và gỡ cài đặt sạch. |
| **Sileo Repository & CI/CD** | `Repository/*`, `Scripts/build_repo.py`, `.github/workflows/build-and-publish.yml` | Hoàn thành | Sinh `Packages`, `Packages.gz`, `Packages.bz2`, `Release`, native depiction JSON, trang chủ Dark Mode cho GitHub Pages không dùng URL giả. |

---

## 2. Những hạng mục CHƯA thể thực hiện tại máy Windows hiện tại (Minh bạch tuyệt đối)

| Hạng mục | Trạng thái | Nguyên nhân thực tế | Cách hoàn tất ngay |
|---|---|---|---|
| **Biên dịch thực tế `Releases/MultiClone.deb`** | **Chưa biên dịch trên máy Windows này** | Máy hiện tại là Windows không có WSL distro, Docker, clang/LLVM cho iOS, Theos, iOS SDK hay `dpkg-deb`. Theo đúng nguyên tắc, **KHÔNG tạo file `.deb` giả**. | Đẩy thư mục `MultiClone` lên GitHub để `.github/workflows/build-and-publish.yml` tự build trên `macos-15` (Xcode + iOS SDK thật), **hoặc** chạy `./Scripts/setup_theos.sh && ./Scripts/build.sh` trên macOS / Linux / WSL2. |
| **Kiểm thử chạy thực tế trên iPhone 11 / iOS 18.2 / Dopamine 3.0.7+** | **Chưa kiểm thử trên máy thật** | Không có thiết bị iPhone 11 kết nối trực tiếp trong phiên làm việc này. | Sau khi có `MultiClone.deb` thật, cài qua Sileo theo [INSTALL_IPHONE11.md](INSTALL_IPHONE11.md), bấm **IPC Ping** trong Cài đặt, và kiểm thử Auto Close + IPA Inspector trực tiếp trên iPhone 11. |

---

## 3. Phân loại kết quả kiểm thử (12 hạng mục bắt buộc)

Xem chi tiết thực thi tự động tại `Tests/run_all_tests.py`:
- **Kiểm thử tĩnh & giả lập trên máy host (đã chạy tự động & PASS):**
  1. Cấu trúc source & phân tách 10 module.
  2. Cú pháp Objective-C / Logos (`@interface/@end`, `@implementation/@end`, `%ctor`, cân bằng ngoặc, include headers tồn tại, không có ký hiệu trùng lặp, không còn `TODO`).
  3. Cấu trúc `Makefile` (root, Tweak, Manager) chuẩn Theos rootless `arm64 arm64e`.
  4. Kiểm tra toàn bộ tệp `.plist` (`Info.plist`, `entitlements.plist`, `auto-close-defaults.plist`, `MultiClone.plist`).
  5. Kiểm tra `control` và đồng bộ giữa `control` gốc và `Packaging/control`.
  6. Kiểm tra danh sách dependency (`firmware`, `mobilesubstrate | ellekit`, zero external CocoaPods).
  7. Kiểm thử đóng gói DEB mô phỏng & kiểm thử `Scripts/build_repo.py` đọc `.deb` thực tế (tạo gói `.deb` tạm thời trong `tempfile` để kiểm thử parser `ar` + `control.tar.gz` + `Packages.bz2` + `Release`, sau đó xóa sạch — không lưu file giả vào `Releases/`).
  8. Kiểm tra cấu trúc rootless (`/var/jb`, không ghi thẳng vào `/` trừ `DEBIAN/`).
  9. Kiểm thử logic Auto Close (chặn system app `com.apple.*`, chặn non-managed app, chặn đóng app đang mở, xác nhận bảo toàn mặc định an toàn `autoCloseEnabled=false`).
  10. Kiểm tra script cài đặt & gỡ cài đặt (`postinst`, `prerm`, `postrm` có `uicache`, chỉ xóa trong `/var/mobile/Library/MultiClone`).
  11. Kiểm thử cơ chế bảo vệ dữ liệu ứng dụng gốc (Zip Slip rejection, kiểm tra `MCIsPathStrictlyInsideDirectory`, từ chối trùng `sourceBundleID`, từ chối FairPlay DRM `cryptid=1`).
  12. Kiểm tra quy tắc tương thích iOS 18.2 (cô lập `FBSSystemService`/`LSApplicationWorkspace` trong `@try/@catch`, kiểm tra `NSMethodSignature`, không dùng API đã loại bỏ không có fallback).
- **Kiểm thử build thực tế (chờ môi trường macOS/Linux/GitHub Actions):** Biên dịch `MultiClone.deb` và chạy `Scripts/verify_package.sh`.
- **Kiểm thử thiết bị thật (chờ iPhone 11 iOS 18.2 Dopamine 3.0.7+):** Cài đặt từ Sileo, Respring, Ping/Pong SpringBoard, Auto Close, nhập IPA thực tế.
