#!/bin/bash
# Static validation for the clean NR3053 build tree.
# This script does not update feeds, download sources, or compile firmware.

set -euo pipefail
umask 022

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DEFCONFIG="defconfig/nr3053-clean.config"
PROFILE="target/linux/mediatek/image/filogic-ext.mk"
IMAGE_MAKEFILE="target/linux/mediatek/image/Makefile"
DTS="target/linux/mediatek/dts-ext/mt7981b-viettel-nr3053.dts"
PLATFORM_UPGRADE="target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
TURBOACC_DIR="package/mtk/applications/luci-app-turboacc-mtk"
TURBOACC_MAKEFILE="$TURBOACC_DIR/Makefile"
TURBOACC_DEFAULTS="$TURBOACC_DIR/root/etc/uci-defaults/turboacc"
UBOOT_MAKEFILE="package/boot/uboot-mediatek/Makefile"
UBOOT_PATCH="package/boot/uboot-mediatek/patches/504-add-viettel-nr3053.patch"

required_files=(
    REPO-FIX-REPORT.md
    "$DEFCONFIG"
    "$PROFILE"
    "$IMAGE_MAKEFILE"
    "$DTS"
    "$PLATFORM_UPGRADE"
    "$TURBOACC_MAKEFILE"
    "$TURBOACC_DEFAULTS"
    "$UBOOT_MAKEFILE"
    "$UBOOT_PATCH"
    custom-files/vi-mtwifi-cfg.po
    custom-files/vi-turboacc.po
    scripts/install-deps.sh
    scripts/nr3053-package-policy.sh
    scripts/restore-exec-permissions.sh
    scripts/prepare-build.sh
    scripts/build-viettel.sh
    scripts/sync-upstream.sh
    scripts/unlock/unlock_viettel.py
    .github/workflows/ci.yml
    .github/workflows/dev-build.yml
    .github/workflows/build-release.yml
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Required file is missing: $file" >&2
        exit 1
    fi
done

# shellcheck source=scripts/nr3053-package-policy.sh
source scripts/nr3053-package-policy.sh

# Project script syntax checks.
bash -n scripts/install-deps.sh
bash -n scripts/nr3053-package-policy.sh
bash -n scripts/restore-exec-permissions.sh
bash -n scripts/validate-nr3053-repo.sh
bash -n scripts/prepare-build.sh
bash -n scripts/build-viettel.sh
bash -n scripts/sync-upstream.sh

# Reject accidental trailing whitespace in files owned by this NR3053 fork.
python3 - <<'PY'
from pathlib import Path

paths = [
    Path("README.md"),
    Path("NR3053-CLEAN-CHANGES.md"),
    Path("REPO-FIX-REPORT.md"),
    Path("docs/huong-dan-nap-firmware.md"),
    Path("defconfig/nr3053-clean.config"),
    Path("target/linux/mediatek/image/filogic-ext.mk"),
    Path("package/mtk/applications/luci-app-turboacc-mtk/Makefile"),
    Path("package/mtk/applications/luci-app-turboacc-mtk/root/etc/uci-defaults/turboacc"),
]
paths.extend(sorted(Path(".github/workflows").glob("*.y*ml")))
paths.extend(
    Path(name)
    for name in (
        "scripts/install-deps.sh",
        "scripts/nr3053-package-policy.sh",
        "scripts/restore-exec-permissions.sh",
        "scripts/validate-nr3053-repo.sh",
        "scripts/prepare-build.sh",
        "scripts/build-viettel.sh",
        "scripts/sync-upstream.sh",
    )
)

errors = []
for path in paths:
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.endswith((" ", "\t")):
            errors.append(f"{path}:{number}: trailing whitespace")

if errors:
    raise SystemExit("\n".join(errors))
PY

# Compile Python source in memory so validation does not create __pycache__.
python3 - scripts/unlock/unlock_viettel.py <<'PY'
from pathlib import Path
import sys

for name in sys.argv[1:]:
    path = Path(name)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

mapfile -t selected_devices < <(
    grep '^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_.*=y$' "$DEFCONFIG" || true
)

if [ "${#selected_devices[@]}" -ne 1 ] ||
   [ "${selected_devices[0]:-}" != 'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_viettel_nr3053=y' ]; then
    echo "ERROR: $DEFCONFIG must select only viettel_nr3053." >&2
    if [ "${#selected_devices[@]}" -eq 0 ]; then
        echo "  <none>" >&2
    else
        printf '  %s\n' "${selected_devices[@]}" >&2
    fi
    exit 1
fi

for package in "${NR3053_REQUIRED_PACKAGES[@]}"; do
    if ! grep -Fqx "CONFIG_PACKAGE_${package}=y" "$DEFCONFIG"; then
        echo "ERROR: Required package is not enabled in $DEFCONFIG: $package" >&2
        exit 1
    fi
done

for package in "${NR3053_FORBIDDEN_PACKAGES[@]}"; do
    if grep -Fqx "CONFIG_PACKAGE_${package}=y" "$DEFCONFIG"; then
        echo "ERROR: Forbidden package is enabled in $DEFCONFIG: $package" >&2
        exit 1
    fi
done

for symbol in "${NR3053_BBR_SYMBOLS[@]}"; do
    if grep -Fqx "${symbol}=y" "$DEFCONFIG"; then
        echo "ERROR: BBR symbol is enabled in $DEFCONFIG: $symbol" >&2
        exit 1
    fi
done

if grep -RIni --exclude-dir='.git' -- 'bbr' "$TURBOACC_DIR" >/dev/null; then
    echo "ERROR: TurboACC MTK still contains a BBR reference." >&2
    grep -RIni --exclude-dir='.git' -- 'bbr' "$TURBOACC_DIR" >&2 || true
    exit 1
fi

if ! grep -Fq '+kmod-mediatek_hnat' "$TURBOACC_MAKEFILE"; then
    echo "ERROR: TurboACC MTK must depend on kmod-mediatek_hnat." >&2
    exit 1
fi

if ! grep -Fq "option tcpcca 'cubic'" "$TURBOACC_DEFAULTS"; then
    echo "ERROR: TurboACC MTK must default to the cubic TCP congestion control." >&2
    exit 1
fi

profile_block="$({
    awk '
        /^define Device\/viettel_nr3053$/ { found=1 }
        found { print }
        found && /^endef$/ { exit }
    ' "$PROFILE"
} || true)"

if [ -z "$profile_block" ]; then
    echo "ERROR: Device/viettel_nr3053 was not found in $PROFILE." >&2
    exit 1
fi

profile_count="$(grep -Rhs '^define Device/viettel_nr3053$' target/linux/mediatek/image --include='*.mk' | wc -l)"
if [ "$profile_count" -ne 1 ]; then
    echo "ERROR: Expected exactly one Device/viettel_nr3053 definition; found $profile_count." >&2
    exit 1
fi

profile_requirements=(
    'DEVICE_DTS := mt7981b-viettel-nr3053'
    'SUPPORTED_DEVICES := viettel,nr3053 sdmc,nr3053'
    'UBINIZE_OPTS := -E 5'
    'BLOCKSIZE := 128k'
    'PAGESIZE := 2048'
    'IMAGE_SIZE := 229376k'
    'KERNEL_IN_UBI := 1'
    'UBOOTENV_IN_UBI := 1'
    'IMAGES := sysupgrade.itb'
    'KERNEL_INITRAMFS_SUFFIX := -recovery.itb'
    'ARTIFACTS := preloader.bin bl31-uboot.fip'
    'ARTIFACT/preloader.bin := mt7981-bl2 spim-nand-ddr3'
    'ARTIFACT/bl31-uboot.fip := mt7981-bl31-uboot viettel_nr3053'
)

for requirement in "${profile_requirements[@]}"; do
    if ! grep -Fq "$requirement" <<<"$profile_block"; then
        echo "ERROR: NR3053 profile is missing: $requirement" >&2
        exit 1
    fi
done

profile_removed_packages=(
    default-settings
    default-settings-chn
    default-settings-vn
    kmod-usb3
    kmod-usb-ledtrig-usbport
    automount
    autosamba
)
for package in "${profile_removed_packages[@]}"; do
    if ! grep -Eq "(^|[[:space:]])-${package}([[:space:]\\]|$)" <<<"$profile_block"; then
        echo "ERROR: NR3053 profile must explicitly remove default package: $package" >&2
        exit 1
    fi
done

if ! grep -Fqx 'TARGET_DEVICES += viettel_nr3053' "$PROFILE"; then
    echo "ERROR: NR3053 is not registered in TARGET_DEVICES." >&2
    exit 1
fi

if grep -q 'filogic-ext-viettel-fork.mk' "$IMAGE_MAKEFILE" ||
   [ -e target/linux/mediatek/image/filogic-ext-viettel-fork.mk ]; then
    echo "ERROR: Stale duplicate Viettel image-profile override is still present." >&2
    exit 1
fi

if [ "$(grep -Fc 'include filogic-ext.mk' "$IMAGE_MAKEFILE")" -ne 1 ]; then
    echo "ERROR: filogic-ext.mk must be included exactly once." >&2
    exit 1
fi

uboot_block="$({
    awk '
        /^define U-Boot\/mt7981_viettel_nr3053$/ { found=1 }
        found { print }
        found && /^endef$/ { exit }
    ' "$UBOOT_MAKEFILE"
} || true)"

if [ -z "$uboot_block" ]; then
    echo "ERROR: U-Boot/mt7981_viettel_nr3053 is missing." >&2
    exit 1
fi

uboot_requirements=(
    'BUILD_DEVICES:=viettel_nr3053'
    'UBOOT_CONFIG:=mt7981_viettel_nr3053'
    'UBOOT_IMAGE:=u-boot.fip'
    'BL2_BOOTDEV:=spim-nand'
    'BL2_SOC:=mt7981'
    'BL2_DDRTYPE:=ddr3'
    'DEPENDS:=+trusted-firmware-a-mt7981-spim-nand-ddr3'
)
for requirement in "${uboot_requirements[@]}"; do
    if ! grep -Fq "$requirement" <<<"$uboot_block"; then
        echo "ERROR: NR3053 U-Boot definition is missing: $requirement" >&2
        exit 1
    fi
done

uboot_patch_requirements=(
    'CONFIG_DEFAULT_DEVICE_TREE="mt7981-viettel_nr3053"'
    'reg = <0x40000000 0x20000000>;'
    'reg = <0x0 0x100000>;'
    'reg = <0x100000 0x100000>;'
    'reg = <0x200000 0x200000>;'
    'reg = <0x400000 0x200000>;'
    'reg = <0x600000 0xea00000>;'
    'CONFIG_ENV_IS_IN_UBI=y'
    'CONFIG_ENV_UBI_PART="ubi"'
    'CONFIG_ENV_UBI_VOLUME="ubootenv"'
    'CONFIG_ENV_UBI_VOLUME_REDUND="ubootenv2"'
    'bootfile=immortalwrt-mediatek-filogic-viettel_nr3053-initramfs-recovery.itb'
    'bootfile_upg=immortalwrt-mediatek-filogic-viettel_nr3053-squashfs-sysupgrade.itb'
    'ubi_read_production=ubi read $loadaddr fit'
    'ubi_write_production=ubi check fit'
)
for requirement in "${uboot_patch_requirements[@]}"; do
    if ! grep -Fq "$requirement" "$UBOOT_PATCH"; then
        echo "ERROR: NR3053 U-Boot patch is missing: $requirement" >&2
        exit 1
    fi
done

python3 - "$DTS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

required_text = (
    'compatible = "viettel,nr3053", "mediatek,mt7981";',
    'reg = <0x0 0x40000000 0x0 0x20000000>;',
    'volname = "fit";',
    'volname = "ubootenv";',
    'volname = "ubootenv2";',
)
for item in required_text:
    if item not in text:
        raise SystemExit(f"NR3053 DTS is missing: {item}")

starts = list(re.finditer(r'(?m)^\s*partition@[0-9a-fA-F]+\s*\{', text))
partitions = {}
for index, match in enumerate(starts):
    end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
    block = text[match.start():end]
    label_match = re.search(r'label\s*=\s*"([^"]+)"\s*;', block)
    if label_match:
        partitions[label_match.group(1)] = block

expected = {
    "BL2": ("reg = <0x0 0x100000>;", True),
    "u-boot-env": ("reg = <0x100000 0x100000>;", True),
    "Factory": ("reg = <0x200000 0x200000>;", True),
    "FIP": ("reg = <0x400000 0x200000>;", True),
    "ubi": ("reg = <0x600000 0xea00000>;", False),
}

for label, (reg, read_only) in expected.items():
    block = partitions.get(label)
    if block is None:
        raise SystemExit(f"NR3053 DTS partition is missing: {label}")
    if reg not in block:
        raise SystemExit(f"NR3053 DTS partition {label} has unexpected geometry")
    if read_only and "read-only;" not in block:
        raise SystemExit(f"NR3053 DTS partition {label} must be read-only")

if 'compatible = "linux,ubi";' not in partitions["ubi"]:
    raise SystemExit("NR3053 UBI partition is missing linux,ubi compatibility")
PY

for board in 'viettel,nr3053' 'sdmc,nr3053'; do
    if ! grep -Fq "$board" "$PLATFORM_UPGRADE"; then
        echo "ERROR: platform upgrade code does not support: $board" >&2
        exit 1
    fi
done

legacy_paths=(
    custom-files/99-viettel-custom-defaults
    custom-files/99-viettel-services-defaults
    custom-files/default.vi.po
    custom-files/more.vi.po
    custom-files/etc
    custom-files/vi-upnp.po
    defconfig/viettel-only.config
    docs/huong-dan-tinh-nang-mo-rong.md
    package/viettel/luci-app-nr3053-throughwall
    target/linux/mediatek/filogic/base-files/lib/viettel-nr3053-throughwall.sh
    target/linux/mediatek/filogic/base-files/etc/init.d/viettel-nr3053-throughwall
    target/linux/mediatek/filogic/base-files/etc/uci-defaults/99-viettel-nr3053-throughwall
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/net/99-viettel-nr3053-throughwall
)

for path in "${legacy_paths[@]}"; do
    if [ -e "$path" ]; then
        echo "ERROR: Legacy service/configuration path must be removed: $path" >&2
        exit 1
    fi
done

mapfile -t custom_files < <(find custom-files -type f -printf '%P\n' | sort)
expected_custom_files=(
    vi-mtwifi-cfg.po
    vi-turboacc.po
)
if [ "${#custom_files[@]}" -ne "${#expected_custom_files[@]}" ]; then
    echo "ERROR: custom-files must contain only the two retained translation files." >&2
    printf '  %s\n' "${custom_files[@]}" >&2
    exit 1
fi
for index in "${!expected_custom_files[@]}"; do
    if [ "${custom_files[$index]}" != "${expected_custom_files[$index]}" ]; then
        echo "ERROR: Unexpected custom file: ${custom_files[$index]}" >&2
        exit 1
    fi
done

if [ "$(grep -Ec '^[[:space:]]*make[[:space:]]+defconfig([[:space:]]|$)' scripts/prepare-build.sh)" -ne 1 ]; then
    echo "ERROR: prepare-build.sh must invoke make defconfig exactly once." >&2
    exit 1
fi
if grep -Fq 'olddefconfig' scripts/prepare-build.sh; then
    echo "ERROR: prepare-build.sh must not invoke olddefconfig." >&2
    exit 1
fi

if grep -RIn --include='*.yml' --include='*.yaml' -E 'viettel-only\.config|NR3053[[:space:]]*&[[:space:]]*32X6' .github/workflows >/dev/null; then
    echo "ERROR: A workflow still references the legacy config or 32X6 release." >&2
    exit 1
fi

if ! grep -Fq 'ref: ${{ needs.prepare.outputs.tag }}' .github/workflows/build-release.yml; then
    echo "ERROR: Release workflow must checkout the exact validated tag." >&2
    exit 1
fi

if [ "$(grep -RhsF 'bash scripts/build-viettel.sh defconfig/nr3053-clean.config' .github/workflows --include='*.yml' --include='*.yaml' | wc -l)" -lt 2 ]; then
    echo "ERROR: Dev and release workflows must build nr3053-clean.config." >&2
    exit 1
fi

workflow_requirements=(
    'actions/checkout@v6'
    'actions/cache@v5'
    'actions/upload-artifact@v7'
    'actions/download-artifact@v8'
    'softprops/action-gh-release@v3'
)
for requirement in "${workflow_requirements[@]}"; do
    if ! grep -RqsF "$requirement" .github/workflows; then
        echo "ERROR: Workflow action is missing: $requirement" >&2
        exit 1
    fi
done

if find . -type d -name __pycache__ -not -path './.git/*' -print -quit | grep -q .; then
    echo "ERROR: Python bytecode cache must not be committed or packaged." >&2
    exit 1
fi

echo "OK: NR3053 repository static validation passed"
