# MultiClone v1.0.0 — iOS 18.2 / Dopamine 3.0.7+ (Rootless)

Công cụ miễn phí (không yêu cầu license) giúp **phân tích IPA chuyên sâu**, **tạo cấu hình bản sao cô lập**, **quản lý nhiều bản clone** với giao diện **Dark Mode**, kèm tính năng **Auto Close Previous Managed App** an toàn cho **iPhone 11 / iOS 18.2 / Dopamine Rootless / Sileo**.

---

## Kiến trúc tổng thể

```
MultiClone/
├── Source/                  # 8 module lõi độc lập (Obj-C/C + Python CLI)
│   ├── MultiCloneCore/      # Hằng số rootless, Models, ZipArchive (libz + chống Zip Slip), MachOInspector, PrivateAPIBridge
│   ├── IPAInspector/        # Phân tích IPA: Bundle ID, Icon, Mach-O, FairPlay DRM, Frameworks, Extensions, Entitlements
│   ├── CloneEngine/         # Tạo cấu hình clone có staging giao dịch & tự khôi phục (rollback) khi lỗi
│   ├── DataManager/         # Quản lý registry JSON, dung lượng thực, cô lập thư mục, chặn xóa ngoài phạm vi
│   ├── IconManager/         # Trích xuất, resize 120x120 / 180x180 và áp dụng icon tùy chỉnh
│   ├── AutoClose/           # Client quản lý Auto Close, xác nhận trước khi đóng, IPC 2 lớp & Ping/Pong
│   ├── Settings/            # Quản lý cấu hình CFPreferences/IPC + Keychain secure storage
│   ├── Logger/              # Nhật ký xoay vòng 512KB có che giấu token/mật khẩu nhạy cảm
│   └── CLI/                 # Công cụ dòng lệnh ipa_inspect.py & mc_manifest.py (tương thích ngược v0.3)
├── Manager/
│   └── MultiCloneManager/   # Ứng dụng quản lý UIKit Dark Mode (Trang chủ, Tạo Clone, Quản lý Clone, Cài đặt, Nhật ký)
├── Tweak/
│   └── MultiCloneSpringBoard/ # Tweak SpringBoard rootless (Tweak.xm, MCAutoClose, MultiClone.plist)
├── Resources/               # Icon ứng dụng (@2x, @3x), cấu hình mặc định, manifest mẫu
├── Packaging/               # control, DEBIAN/{postinst,prerm,postrm}, dependencies.txt
├── Repository/              # Sileo APT Repository sẵn sàng xuất bản lên GitHub Pages
├── Scripts/                 # setup_theos.sh, build.sh, verify_package.sh, build_repo.py, build_repo.sh
├── Tests/                   # Bộ kiểm thử tự động toàn diện (cấu trúc, cú pháp Obj-C/Logos, Mach-O/DRM, AutoClose, Rootless)
├── Documentation/           # Hướng dẫn cài đặt iPhone 11, cập nhật, gỡ cài đặt, xuất bản Sileo Repo, báo cáo tính năng
└── Releases/                # Nơi chứa MultiClone.deb, SHA256SUMS.txt, build.log sau khi biên dịch thực tế
```

---

## Minh bạch kỹ thuật & Giới hạn tương thích

MultiClone **không tuyên bố mọi IPA đều có thể clone hoạt động 100%**. Bộ phân tích `MCIPAInspector` tự động kiểm tra và cảnh báo rõ ràng:

- **Chặn tuyệt đối (Incompatible):**
  - Binary bị mã hóa **FairPlay DRM** (`LC_ENCRYPTION_INFO_64` có `cryptid != 0`) — MultiClone **không bypass DRM**.
  - Thiếu kiến trúc `arm64`/`arm64e` cho iPhone 11 (A13).
  - Ứng dụng hệ thống Apple (`com.apple.*`) hoặc công cụ jailbreak cốt lõi.
- **Cảnh báo rõ ràng (Partial / Warning):**
  - Khai báo `com.apple.security.application-groups` (App Groups), `keychain-access-groups`, `aps-environment` (Push Notifications), `associated-domains`.
  - Có App Extensions (`.appex`) cần chữ ký & tiền tố Bundle ID đồng bộ.
  - Các ứng dụng bên thứ ba có xác minh máy chủ / toàn vẹn ứng dụng (Facebook, Zalo, TikTok...) — MultiClone **không bypass cơ chế chống gian lận hay xác thực tài khoản**.

---

## Biên dịch thực tế `.deb` (macOS / Linux / WSL2 hoặc GitHub Actions)

### Cách 1: Tự động biên dịch thật trên GitHub Actions (khuyên dùng nếu dùng Windows)
Workflow [build-and-publish.yml](.github/workflows/build-and-publish.yml) chạy trên `macos-15` với **Xcode + iOS SDK thật + Theos + ldid + dpkg**, tự động:
1. Chạy toàn bộ bộ kiểm thử `Tests/run_all_tests.py`.
2. Biên dịch thực tế `MultiClone.dylib` (`arm64` + `arm64e`) và `MultiCloneManager.app` (`arm64` + `arm64e`).
3. Đóng gói `Releases/MultiClone.deb` chuẩn rootless và xác minh bằng `Scripts/verify_package.sh`.
4. Tạo `Releases/SHA256SUMS.txt`, cập nhật chỉ mục Sileo Repo và xuất bản lên GitHub Pages.

### Cách 2: Biên dịch trực tiếp trên macOS / Linux / WSL2
```bash
cd MultiClone
./Scripts/setup_theos.sh
export THEOS="$HOME/theos"
./Scripts/build.sh
./Scripts/build_repo.sh ./Releases ./Repository
```

---

## Tài liệu chi tiết
- [Hướng dẫn cài đặt trên iPhone 11 (iOS 18.2 / Dopamine)](Documentation/INSTALL_IPHONE11.md)
- [Hướng dẫn kết nối GitHub Pages tạo Sileo Repository riêng](Documentation/GITHUB_PAGES_SILEO.md)
- [Hướng dẫn cập nhật phiên bản](Documentation/UPDATE_GUIDE.md)
- [Hướng dẫn gỡ cài đặt sạch](Documentation/UNINSTALL_GUIDE.md)
- [Báo cáo tính năng đã hoàn thành & kiểm thử](Documentation/FEATURE_STATUS_REPORT.md)
- [Trạng thái build trong môi trường hiện tại](Releases/BUILD_STATUS.md)
