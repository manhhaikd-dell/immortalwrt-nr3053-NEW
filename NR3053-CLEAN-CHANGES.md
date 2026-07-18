# NR3053 clean build changes

## Phần cứng và image

- Chỉ chọn `viettel_nr3053` trong `defconfig/nr3053-clean.config`.
- Giữ DTS 512 MiB RAM và layout NAND: BL2, u-boot-env, Factory, FIP, UBI.
- Giữ `IMAGE_SIZE := 229376k`, UBI/FIT, recovery, FIP và preloader.
- Thêm `sdmc,nr3053` trực tiếp vào `SUPPORTED_DEVICES` của profile gốc.
- Xóa file override profile trùng lặp `filogic-ext-viettel-fork.mk` để tránh lệch layout khi upstream thay đổi.

## Firmware sạch

- Giữ LuCI Bootstrap, MT WiFi, HNAT, NF flow, WARP, TurboACC MTK và AdGuard Home package.
- Loại Adblock, DDNS, UPnP, WireGuard, Aurora, ThroughWall, ZRAM, Tailscale và toàn bộ gói regional `default-settings*`.
- Xóa toàn bộ ThroughWall từng được chép thẳng vào `target/.../base-files`; trước đây nó vẫn vào image dù package LuCI bị tắt.
- Xóa các custom first-boot script và file Adblock/UPnP cũ.
- Profile NR3053 chủ động loại `default-settings*`, USB3, automount và autosamba để không bị kéo lại từ default package list.
- Bỏ dependency bắt buộc `+kmod-tcp-bbr` khỏi `luci-app-turboacc-mtk`; `kmod-tcp-bbr` hiện bị cấm trong config và manifest.

## Build và CI

- `make defconfig` chỉ chạy một lần; không sửa `.config` sau đó và không dùng `make olddefconfig`.
- Release workflow checkout đúng tag khi chạy thủ công.
- Đồng bộ workflow với mục tiêu duy nhất NR3053; không còn mô tả release 32X6.
- Dùng action Node 24: checkout v6, cache v5, upload-artifact v7, download-artifact v8 và action-gh-release v3.
- Cache chỉ được lưu sau job thành công bởi `actions/cache` post-step.
- Artifact được kiểm tra đủ 4 image, manifest và metadata trước khi upload.
- `sha256sums` được tạo lại chỉ cho các file thật sự phát hành.

## An toàn flash

- LuCI/sysupgrade chỉ dùng file `*-squashfs-sysupgrade.itb`.
- `preloader.bin` và `bl31-uboot.fip` không dùng cho sysupgrade thông thường.
- Chạy `sysupgrade -T` trước khi flash.
