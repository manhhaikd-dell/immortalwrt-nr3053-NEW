# ImmortalWrt NR3053 Clean Build

Bản ImmortalWrt dành riêng cho **Viettel/SDMC NR3053**, nền MediaTek Filogic MT7981.
Workflow mặc định chỉ build một profile: `viettel_nr3053`.

## Phần cứng mục tiêu

| Thành phần | Thông số |
|---|---|
| SoC | MediaTek MT7981B, ARM64 Cortex-A53 |
| RAM | 512 MiB DDR3 |
| NAND | 256 MiB-class SPI-NAND |
| Layout Linux nhìn thấy | BL2 1 MiB, u-boot-env 1 MiB, Factory 2 MiB, FIP 2 MiB, UBI 234 MiB |
| Ethernet | 1 WAN + 3 LAN qua MT7531 |
| Wi-Fi | MediaTek MT WiFi 2.4 GHz + 5 GHz |
| USB | Không sử dụng; DTS và profile tắt USB |

Profile image giữ nguyên hình học NAND/UBI của NR3053:

```text
IMAGE_SIZE=229376k
BLOCKSIZE=128k
PAGESIZE=2048
KERNEL_IN_UBI=1
UBOOTENV_IN_UBI=1
```

Metadata của `sysupgrade.itb` chấp nhận cả:

```text
viettel,nr3053
sdmc,nr3053
```

## Thành phần firmware

Giữ lại:

- LuCI và theme Bootstrap
- MediaTek MT WiFi và giao diện MT WiFi
- MediaTek HNAT, NF flow và WARP
- TurboACC MTK
- AdGuard Home package
- Tiếng Việt cho các giao diện MediaTek được giữ lại
- Footer LuCI tùy biến

Loại bỏ khỏi image:

- Adblock
- DDNS
- UPnP
- WireGuard
- Aurora
- ThroughWall
- ZRAM
- Tailscale
- Các gói `default-settings`, `default-settings-chn` và `default-settings-vn`
- BBR và `kmod-tcp-bbr`

Không nhúng cấu hình DNS, AdGuard Home YAML, mật khẩu, khóa VPN, regional defaults hoặc script thiết lập dịch vụ ở lần khởi động đầu.

> `luci-app-turboacc-mtk` trong cây nguồn ban đầu kéo `kmod-tcp-bbr` bắt buộc. Bản này đã bỏ dependency đó; TurboACC mặc định dùng `cubic` và BBR không có trong image.

## Build cục bộ

Ubuntu/Debian:

```bash
bash scripts/restore-exec-permissions.sh
bash scripts/install-deps.sh
bash scripts/build-viettel.sh
```

Có thể giới hạn số luồng:

```bash
JOBS=4 bash scripts/build-viettel.sh
```

Build gồm các bước:

1. Kiểm tra cấu trúc repo và profile NR3053.
2. Update/install feeds.
3. Gắn footer và bản dịch.
4. Chạy `make defconfig` đúng một lần.
5. Kiểm tra package bắt buộc/cấm.
6. Download source và compile.
7. Kiểm tra manifest, metadata sysupgrade và artifact.
8. Tạo thư mục `dist/` cùng `sha256sums`.

## GitHub Actions

- `CI`: kiểm tra shell, Python, YAML và quy tắc repo.
- `Dev Build`: build tự động khi thay đổi mã trên `main`.
- `Build Release`: build đúng tag `vMAJOR.MINOR.PATCH` rồi tạo GitHub Release.

Tạo release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Hoặc chạy `Build Release` thủ công và nhập một tag đã tồn tại.

## Artifact

`dist/` chứa:

```text
*-squashfs-sysupgrade.itb
*-initramfs-recovery.itb
*-bl31-uboot.fip
*-preloader.bin
*.manifest
sha256sums
```

### File dùng bình thường

Chỉ dùng:

```text
*-squashfs-sysupgrade.itb
```

để nâng cấp qua LuCI hoặc lệnh `sysupgrade`.

Trước khi flash:

```bash
sysupgrade -T /tmp/firmware.itb
```

Nếu chuyển từ firmware/build có layout hoặc cấu hình khác, nên nâng cấp sạch:

```bash
sysupgrade -n /tmp/firmware.itb
```

`preloader.bin` và `bl31-uboot.fip` là bootloader, không flash qua LuCI/sysupgrade. Sai file hoặc mất điện khi ghi BL2/FIP có thể làm thiết bị không khởi động.

Xem [hướng dẫn nạp firmware](docs/huong-dan-nap-firmware.md).

## Lưu ý về firmware gốc Viettel và bootloader

Repo này **không tạo `factory.itb`**. Giao diện web của firmware gốc có thể kiểm tra vendor header hoặc chữ ký nên không được giả định rằng nó sẽ nhận `sysupgrade.itb`.

Image của repo dùng UBI volume `fit`; vì vậy bootloader phải biết đọc volume `fit`. Nếu thiết bị vẫn dùng ROM/bootloader gốc hoặc một bản OpenWrt cũ có các volume `kernel` + `ubi_rootfs`, chỉ chạy `sysupgrade -T` thành công **chưa đủ** để chứng minh máy sẽ boot được image mới.

Quy trình cài lần đầu an toàn là:

1. Backup `mtd0` đến `mtd3`.
2. Nạp U-Boot/FIP của repo **tạm thời vào RAM** bằng UART/BootROM, rồi boot `initramfs-recovery.itb` để test phần cứng.
3. Chỉ khi test đúng NR3053 mới cân nhắc ghi `bl31-uboot.fip` vào phân vùng `FIP` (`mtd3`). Không cần ghi `preloader.bin` trong quy trình thông thường.
4. Khởi động U-Boot tương thích và dùng mục có mô tả **Load production system via TFTP then write to NAND** để ghi `sysupgrade.itb` vào UBI.

Như vậy, nâng cấp từ một bản ImmortalWrt tương thích chỉ cần `sysupgrade.itb`; chuyển trực tiếp từ ROM gốc có thể cần đổi **FIP/mtd3** trước. Xem kỹ [hướng dẫn nạp firmware](docs/huong-dan-nap-firmware.md).

## Kiểm tra repo không cần build

```bash
bash scripts/validate-nr3053-repo.sh
```

Script sẽ kiểm tra profile, RAM/NAND DTS, metadata alias, package bắt buộc/cấm, BBR dependency, ThroughWall và các file cấu hình dịch vụ cũ.
