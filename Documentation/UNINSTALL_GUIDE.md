# Hướng dẫn gỡ cài đặt sạch MultiClone

MultiClone được thiết kế để gỡ cài đặt sạch sẽ và **tuyệt đối không làm ảnh hưởng đến các ứng dụng gốc hay dữ liệu ngoài phạm vi `/var/mobile/Library/MultiClone`**.

---

## 1. Gỡ cài đặt thông thường qua Sileo (Giữ lại dữ liệu clone đã xuất)
1. Mở **Sileo** → tab **Packages** → chọn **MultiClone**.
2. Nhấn **Modify** → **Remove** → **Confirm**.
3. Nhấn **Restart SpringBoard (Respring)**.

**Những gì được thực hiện tự động:**
- `prerm` gỡ đăng ký biểu tượng `MultiCloneManager.app` khỏi SpringBoard (`uicache -u`).
- Gỡ bỏ `MultiClone.dylib`, `MultiClone.plist` khỏi `/var/jb/Library/MobileSubstrate/DynamicLibraries/` và `MultiCloneManager.app` khỏi `/var/jb/Applications/`.
- `postrm` dọn sạch thư mục tạm `Staging/` và tệp `ipc_state.plist`.

---

## 2. Gỡ cài đặt hoàn toàn (Purge — Xóa sạch toàn bộ dữ liệu & cấu hình MultiClone)
Nếu bạn muốn xóa cả thư mục `/var/mobile/Library/MultiClone` (gồm registry, icon cache, log, bản xuất IPA) và cấu hình `/var/mobile/Library/Preferences/com.multiclone.manager.plist`:

Chạy qua SSH hoặc NewTerm:
```sh
sudo dpkg --purge com.multiclone.manager
sbreload
```

Hoặc sau khi gỡ qua Sileo, xóa thủ công bằng Filza / terminal:
```sh
rm -rf /var/mobile/Library/MultiClone
rm -f /var/mobile/Library/Preferences/com.multiclone.manager.plist
```

> **Cam kết an toàn:** Thao tác gỡ bỏ và purge chỉ tác động tới các tệp thuộc MultiClone trong `/var/jb/` và `/var/mobile/Library/MultiClone`. Các ứng dụng gốc (Facebook, Zalo, TikTok...) và container dữ liệu gốc của chúng hoàn toàn nguyên vẹn.
