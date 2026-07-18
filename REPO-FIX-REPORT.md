# Báo cáo sửa repo NR3053

Ngày rà soát: 2026-07-18

## Phạm vi

Repo này được chuẩn hóa để workflow mặc định chỉ build profile `viettel_nr3053` cho Viettel/SDMC NR3053:

- RAM 512 MiB DDR3;
- SPI-NAND 256 MiB-class;
- metadata sysupgrade: `viettel,nr3053` và `sdmc,nr3053`;
- LuCI Bootstrap, MT WiFi, HNAT, NF flow, WARP, TurboACC MTK và AdGuard Home package;
- không nhúng cấu hình DNS/AdGuard Home, mật khẩu, khóa VPN hoặc custom first-boot service settings.

## Sửa chính

- Gộp profile NR3053 vào `filogic-ext.mk` và xóa profile override trùng lặp.
- Giữ đúng DTS 512 MiB RAM, NAND/UBI 256 MiB-class và hai board alias.
- Chỉ chọn `viettel_nr3053` trong `defconfig/nr3053-clean.config`.
- Loại Adblock, DDNS, UPnP, WireGuard, Aurora, ThroughWall, ZRAM, Tailscale, BBR và các gói regional `default-settings*` khỏi image.
- Bỏ dependency bắt buộc `kmod-tcp-bbr` của TurboACC MTK; mặc định TCP CCA là `cubic`.
- Xóa ThroughWall và các custom first-boot/service files cũ từng được chép trực tiếp vào root filesystem.
- Chuẩn hóa `prepare-build.sh`: update feeds, gắn footer/bản dịch, sau đó chạy `make defconfig` đúng một lần; không dùng `olddefconfig` và không sửa `.config` sau khi resolve.
- Chuẩn hóa `build-viettel.sh`: download có log/retry, build có retry đơn luồng, kiểm tra manifest, FIT/sysupgrade metadata, đủ artifact và checksum.
- Sửa CI, Dev Build và Build Release để cùng dùng một defconfig, release đúng tag và chỉ công bố NR3053.
- Bổ sung validator dùng chung và script khôi phục executable bit khi repo đi qua ZIP/Windows.
- Viết lại README và hướng dẫn flash, phân biệt rõ sysupgrade thông thường với chuyển đổi bootloader từ ROM gốc.

## Kiểm tra tĩnh đã chạy

- `bash -n` cho toàn bộ script quản lý build của dự án.
- Parse tất cả workflow YAML bằng Ruby và PyYAML BaseLoader.
- Kiểm tra cú pháp từng block Bash trong workflow.
- Compile Python source trong bộ nhớ, không tạo `__pycache__`.
- `git diff --check`.
- `scripts/validate-nr3053-repo.sh`.
- Kiểm tra ZIP sau đóng gói và chạy lại validator từ chính nội dung đã giải nén.

## Giới hạn xác nhận

Môi trường đóng gói không tải được feeds/source từ Internet nên chưa chạy một lượt compile firmware hoàn chỉnh tại chỗ. Hai workflow `Dev Build` và `Build Release` sẽ thực hiện bước build đầy đủ trên GitHub Actions. Validator được đặt trước build để dừng sớm nếu profile, package policy, DTS, U-Boot hoặc workflow bị lệch.

## Cảnh báo flash

- Nâng cấp bình thường chỉ dùng `*-squashfs-sysupgrade.itb` và nên chạy `sysupgrade -T` trước.
- Không flash `preloader.bin` hoặc `bl31-uboot.fip` qua LuCI/sysupgrade.
- Thiết bị còn ROM/bootloader gốc có thể chưa biết boot UBI volume `fit`; đọc `docs/huong-dan-nap-firmware.md` trước khi chuyển đổi.
