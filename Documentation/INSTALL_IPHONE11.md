# Hướng dẫn cài đặt MultiClone trên iPhone 11 (iOS 18.2 / Dopamine 3.0.7+)

## 1. Điều kiện tiên quyết
- **Thiết bị:** iPhone 11 (Apple A13, kiến trúc `arm64e` / `arm64`).
- **Hệ điều hành:** iOS 18.2 (tối thiểu iOS 15.0+).
- **Jailbreak:** Dopamine 3.0.7 trở lên (chế độ **Rootless** với `/var/jb` và **ElleKit** đã kích hoạt).
- **Trình quản lý gói:** Sileo.
- **Khuyến nghị (tùy chọn):** Cài thêm gói `ldid` từ kho Procursus trên Sileo nếu muốn MultiClone hỗ trợ ký ad-hoc cục bộ cho các bản clone IPA hợp lệ.

> **An toàn trước khi cài:** Đảm bảo bạn biết cách vào **Safe Mode** của Dopamine phòng trường hợp xung đột với tweak SpringBoard khác.

---

## 2. Cách 1 — Cài đặt qua Sileo Repository (Khuyên dùng)
1. Hoàn tất xuất bản thư mục `Repository/` lên GitHub Pages theo hướng dẫn trong [GITHUB_PAGES_SILEO.md](GITHUB_PAGES_SILEO.md).
2. Mở **Sileo** trên iPhone 11 → chọn tab **Sources** → nhấn nút **`+`** ở góc trên phải.
3. Nhập URL HTTPS của GitHub Pages repository bạn vừa tạo (ví dụ: `https://<username>.github.io/<repo-name>/`).
4. Tìm kiếm gói **MultiClone** (`com.multiclone.manager`, kiến trúc `iphoneos-arm64`).
5. Nhấn **Get** → **Queue** → **Confirm**.
6. Sau khi cài xong, nhấn **Restart SpringBoard (Respring)** để kích hoạt `MultiCloneSpringBoard` và hiển thị biểu tượng **MultiClone** trên Màn hình chính.

---

## 3. Cách 2 — Cài đặt trực tiếp từ tệp `MultiClone.deb`
1. Kiểm tra mã băm SHA256 của tệp `MultiClone.deb` khớp với `Releases/SHA256SUMS.txt` sinh ra từ bản build thực tế.
2. Chuyển `MultiClone.deb` sang iPhone 11 (qua AirDrop, Filza, hoặc `scp`).
3. Mở bằng **Sileo** (Open in Sileo → Get → Confirm) **hoặc** chạy qua SSH / NewTerm:
   ```sh
   sudo dpkg -i /var/mobile/Downloads/MultiClone.deb
   sudo apt-get install -f
   ```
4. Thực hiện **Respring** (`sbreload` hoặc qua nút của Sileo).

---

## 4. Kiểm tra sau khi cài đặt
1. Mở ứng dụng **MultiClone** trên Màn hình chính.
2. Vào tab **Cài đặt** → nhấn **Kiểm tra SpringBoard Tweak (IPC Ping)**.
3. Nếu hiển thị **`SpringBoard Tweak: Hoạt động`**, hệ thống giao tiếp giữa Manager và SpringBoard đã sẵn sàng.
4. Tính năng **Auto Close Previous App** mặc định **TẮT** (`OFF`). Bạn có thể bật lên và giữ tùy chọn **Xác nhận trước khi đóng** ở trạng thái **BẬT** để an toàn khi chuyển đổi giữa các bản clone.
