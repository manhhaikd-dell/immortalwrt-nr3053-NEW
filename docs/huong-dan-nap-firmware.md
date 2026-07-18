# Hướng dẫn nạp ImmortalWrt cho Viettel/SDMC NR3053

Tài liệu này áp dụng cho profile `viettel_nr3053` trong repo này.

## 1. Phân biệt các file

| File | Công dụng | Có dùng qua LuCI/sysupgrade? |
|---|---|---|
| `*-squashfs-sysupgrade.itb` | Kernel + rootfs OpenWrt/ImmortalWrt | **Có** |
| `*-initramfs-recovery.itb` | Boot hệ thống tạm thời trong RAM | Không |
| `*-bl31-uboot.fip` | ATF/U-Boot trong phân vùng FIP | Không |
| `*-preloader.bin` | BL2/preloader | Không |

Nâng cấp thông thường chỉ dùng `*-squashfs-sysupgrade.itb`.

## 2. Kiểm tra checksum

Trong thư mục chứa firmware:

```bash
sha256sum -c sha256sums
```

Chỉ tiếp tục khi file cần dùng báo `OK`.

## 3. Backup trước khi thay firmware

Trên thiết bị đang chạy Linux/OpenWrt, kiểm tra layout:

```bash
cat /proc/mtd
```

Backup bốn phân vùng quan trọng bằng chính xác các lệnh dưới đây:

```bash
dd if=/dev/mtd0 of=/tmp/mtd0-BL2.bin
dd if=/dev/mtd1 of=/tmp/mtd1-u-boot-env.bin
dd if=/dev/mtd2 of=/tmp/mtd2-Factory.bin
dd if=/dev/mtd3 of=/tmp/mtd3-FIP.bin
sha256sum /tmp/mtd0-BL2.bin /tmp/mtd1-u-boot-env.bin /tmp/mtd2-Factory.bin /tmp/mtd3-FIP.bin
```

Chép các file backup ra máy tính. `Factory` chứa MAC và dữ liệu hiệu chuẩn Wi-Fi riêng của thiết bị.

## 4. Nâng cấp từ OpenWrt/ImmortalWrt đang chạy

Phần này chỉ áp dụng khi thiết bị đã dùng bootloader tương thích với layout FIT/UBI của repo. Kiểm tra trước:

```bash
ubinfo -a 2>/dev/null | grep -E 'Volume name|fit|kernel|ubi_rootfs'
```

Nếu thấy volume `fit` và bootloader hiện tại đã từng boot firmware cùng profile này, có thể nâng cấp bình thường. Nếu chỉ thấy `kernel` + `ubi_rootfs`, dừng lại và đọc mục 5; `sysupgrade -T` chỉ kiểm tra metadata/image, không xác nhận bootloader cũ biết đọc volume `fit`.

Chép file vào `/tmp`, ví dụ:

```bash
scp immortalwrt-mediatek-filogic-viettel_nr3053-squashfs-sysupgrade.itb root@192.168.1.1:/tmp/firmware.itb
```

Kiểm tra tương thích:

```bash
sysupgrade -T /tmp/firmware.itb
```

Chỉ flash khi kiểm tra thành công.

Nâng cấp sạch, khuyến nghị khi chuyển từ build khác:

```bash
sysupgrade -n /tmp/firmware.itb
```

Giữ cấu hình chỉ khi chắc chắn cấu hình cũ tương thích:

```bash
sysupgrade /tmp/firmware.itb
```

Không mất điện và không rút nguồn trong quá trình ghi NAND.

## 5. Cài lần đầu từ firmware gốc Viettel

Repo không tạo `factory.itb`, và `sysupgrade.itb` không mang header/chữ ký của firmware Viettel. Không upload trực tiếp vào web UI gốc rồi ép flash.

Ngoài ra, image của repo được U-Boot đọc từ UBI volume `fit`. ROM gốc hoặc bản OpenWrt cũ có thể dùng layout `firmware`/`firmware2` hoặc `kernel` + `ubi_rootfs`. Trong trường hợp đó, chỉ ghi `sysupgrade.itb` có thể tạo volume mới nhưng bootloader cũ không biết boot nó.

### 5.1. Quy trình thử hoàn toàn trong RAM

Chuẩn bị:

- UART 3.3 V, 115200 8N1;
- `docs/uart_payloads/bl2-viettel-nr3053-ram.bin`;
- file `*-bl31-uboot.fip`;
- file `*-initramfs-recovery.itb`;
- TFTP server trên PC `192.168.1.254/24`.

Dùng `mtk_uartboot` để nạp BL2 RAM payload và FIP vào RAM. Bước này chưa ghi NAND. Sau khi vào U-Boot, chọn mục có mô tả **Boot system via TFTP** hoặc chạy thủ công:

```text
setenv serverip 192.168.1.254
setenv ipaddr 192.168.1.1
tftpboot 0x46000000 immortalwrt-mediatek-filogic-viettel_nr3053-initramfs-recovery.itb
bootm 0x46000000#config-1
```

Trong initramfs, xác nhận:

```bash
cat /tmp/sysinfo/board_name
cat /proc/mtd
free -m
dmesg | grep -i -E 'nand|ubi|factory|eeprom|mt7531'
```

Kết quả phải đúng NR3053, RAM khoảng 512 MiB và layout:

```text
BL2         0x0000000 + 0x100000
u-boot-env  0x0100000 + 0x100000
Factory     0x0200000 + 0x200000
FIP         0x0400000 + 0x200000
ubi         0x0600000 + 0xea00000
```

Nếu Ethernet, NAND, MAC hoặc Wi-Fi calibration không đúng, dừng lại và rút nguồn; vì đang boot RAM nên NAND chưa bị thay đổi.

### 5.2. Chuyển sang U-Boot/FIP tương thích

Sau khi đã backup `mtd0`–`mtd3` và test RAM thành công, quá trình chuyển từ ROM gốc thường cần ghi file `*-bl31-uboot.fip` vào **phân vùng FIP (`mtd3`)**. Đây là thao tác bootloader có rủi ro; mất điện hoặc dùng sai file có thể làm máy không boot bình thường.

Ưu tiên dùng đúng mục U-Boot có mô tả:

```text
Load BL31+U-Boot FIP via TFTP then write to NAND
```

Số thứ tự menu có thể khác theo phiên bản; chọn theo **mô tả**, không chọn theo số nhớ sẵn. Không ghi `preloader.bin`/BL2 trong quy trình chuyển đổi thông thường.

Khi buộc phải ghi từ Linux đã unlock, chỉ thực hiện sau khi xác nhận tên phân vùng và checksum:

```bash
cat /proc/mtd
sha256sum /tmp/fip.bin
mtd write /tmp/fip.bin FIP
sync
```

Lệnh trên cố ý thay đổi `mtd3`; nó không phải sysupgrade thông thường. Giữ file backup FIP gốc ở máy tính.

### 5.3. Ghi firmware vào UBI

Khởi động lại vào U-Boot tương thích. Đặt file `*-squashfs-sysupgrade.itb` trong TFTP rồi chọn mục có mô tả:

```text
Load production system via TFTP then write to NAND
```

U-Boot sẽ tạo/ghi volume `fit` trong phân vùng UBI. Lần chuyển đổi đầu tiên có thể xóa layout OS cũ trong `mtd4`; không mất điện trong bước này.

Sau khi máy boot ImmortalWrt, các lần nâng cấp tiếp theo chỉ cần file `sysupgrade.itb` như mục 4.

## 6. Các phân vùng bị ảnh hưởng

Khi thiết bị đã có bootloader tương thích, sysupgrade chuẩn cho profile này chỉ cập nhật vùng UBI chứa firmware. Nó không chủ động ghi:

```text
mtd0 BL2
mtd1 u-boot-env
mtd2 Factory
mtd3 FIP
```

Các phân vùng này chỉ bị thay đổi khi người dùng cố ý chạy lệnh ghi MTD hoặc chọn mục bootloader tương ứng trong U-Boot. Riêng quá trình chuyển từ ROM gốc ở mục 5 có thể cần chủ động thay `mtd3/FIP`; `mtd0/BL2` vẫn được giữ nguyên trong quy trình thông thường.

## 7. Sau khi flash

Chờ thiết bị boot hoàn tất rồi kiểm tra:

```bash
ubus call system board
cat /proc/mtd
free -m
ip -br link
```

Kết quả mong đợi:

- board tương ứng NR3053;
- khoảng 512 MiB RAM vật lý;
- UBI nằm sau vùng boot 6 MiB;
- Ethernet WAN + 3 LAN xuất hiện;
- không có ThroughWall, ZRAM, WireGuard, UPnP, DDNS hoặc Adblock được cài mặc định.

## 8. Cứu máy

- Boot được U-Boot: dùng initramfs recovery qua TFTP.
- Boot được initramfs: kiểm tra NAND/UBI rồi flash lại sysupgrade.
- Hỏng FIP nhưng BL2 còn chạy: cần recovery FIP đúng thiết bị.
- Hỏng BL2: cần MediaTek BootROM/UART payload; đây là tình huống rủi ro cao.

Không phục hồi `Factory` từ thiết bị khác vì MAC và hiệu chuẩn RF không giống nhau.
