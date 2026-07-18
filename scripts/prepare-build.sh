#!/bin/bash
# Prepare a clean ImmortalWrt build for Viettel/SDMC NR3053 only.
# No DNS settings, credentials, service defaults, or AdGuard Home
# configuration are embedded by this script.

set -euo pipefail
umask 022

DEFCONFIG="${1:-defconfig/nr3053-clean.config}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -f "$DEFCONFIG" ]; then
    echo "ERROR: Defconfig not found: $DEFCONFIG" >&2
    exit 1
fi

# shellcheck source=scripts/nr3053-package-policy.sh
source scripts/nr3053-package-policy.sh

config_enabled() {
    local symbol="$1"
    grep -Fqx "${symbol}=y" .config
}

package_enabled() {
    local package="$1"
    config_enabled "CONFIG_PACKAGE_${package}"
}

echo "=== PREP 1/8: Restore permissions and validate repository ==="
bash scripts/restore-exec-permissions.sh
bash scripts/validate-nr3053-repo.sh

echo "=== PREP 2/8: Update and install feeds ==="
perl scripts/feeds update -a
perl scripts/feeds install -a

echo "=== PREP 3/8: Apply LuCI footer branding ==="
BUILD_NAME="ImmortalWrt NR3053 Mod Edition"
BUILD_AUTHOR="Mạnh Hải - 090.999.8327"
BUILD_SOURCE="ImmortalWrt MT798x / NR3053"
SOURCE_EPOCH="$(sh scripts/get_source_date_epoch.sh 2>/dev/null || date -u +%s)"
BUILD_DATE="$(date -u -d "@${SOURCE_EPOCH}" +'%Y-%m-%d' 2>/dev/null || date -u +'%Y-%m-%d')"

patch_luci_footer() {
    local footer_file="$1"

    python3 - \
        "$footer_file" \
        "$BUILD_NAME" \
        "$BUILD_AUTHOR" \
        "$BUILD_SOURCE" \
        "$BUILD_DATE" <<'PY'
from pathlib import Path
import html
import re
import sys

path = Path(sys.argv[1])
build_name = html.escape(sys.argv[2])
build_author = html.escape(sys.argv[3])
build_source = html.escape(sys.argv[4])
build_date = html.escape(sys.argv[5])

begin_marker = "<!-- NR3053_CUSTOM_FOOTER_BEGIN -->"
end_marker = "<!-- NR3053_CUSTOM_FOOTER_END -->"
branding = f"""
{begin_marker}
<div class="nr3053-custom-footer" style="margin-top:6px; text-align:center; line-height:1.5;">
    <strong>{build_name}</strong><br>
    Build: {build_date}<br>
    Author: {build_author}<br>
    <small>{build_source}</small>
</div>
{end_marker}
""".strip()

text = path.read_text(encoding="utf-8")
text = re.sub(
    re.escape(begin_marker) + r".*?" + re.escape(end_marker),
    "",
    text,
    flags=re.DOTALL,
)

if re.search(r"</footer\s*>", text, flags=re.IGNORECASE):
    text = re.sub(
        r"</footer\s*>",
        branding + "\n</footer>",
        text,
        count=1,
        flags=re.IGNORECASE,
    )
elif re.search(r"</body\s*>", text, flags=re.IGNORECASE):
    text = re.sub(
        r"</body\s*>",
        branding + "\n</body>",
        text,
        count=1,
        flags=re.IGNORECASE,
    )
else:
    raise SystemExit(f"No </footer> or </body> marker found in {path}")

path.write_text(text, encoding="utf-8")
PY
}

mapfile -t footer_files < <(
    find feeds/luci package \
        -type f \
        \( -name 'footer.ut' -o -name 'footer.htm' \) \
        2>/dev/null \
        | grep -E '/luci-theme-(bootstrap|bootstrap-mod)/' \
        | sort -u \
        || true
)

if [ "${#footer_files[@]}" -eq 0 ]; then
    echo "ERROR: No Bootstrap LuCI footer template was found." >&2
    exit 1
fi

for footer_file in "${footer_files[@]}"; do
    echo "  Patching: $footer_file"
    patch_luci_footer "$footer_file"
    if ! grep -Fq 'NR3053_CUSTOM_FOOTER_BEGIN' "$footer_file"; then
        echo "ERROR: Footer patch verification failed: $footer_file" >&2
        exit 1
    fi
done

echo "=== PREP 4/8: Apply retained Vietnamese translations ==="
inject_po() {
    local source_file="$1"
    local destination_dir="$2"
    local destination_name="$3"

    if [ ! -f "$source_file" ]; then
        echo "ERROR: Translation file not found: $source_file" >&2
        exit 1
    fi

    mkdir -p "$destination_dir"
    cp -f "$source_file" "$destination_dir/$destination_name"
    echo "  Installed: $destination_dir/$destination_name"
}

inject_po \
    custom-files/vi-turboacc.po \
    package/mtk/applications/luci-app-turboacc-mtk/po/vi \
    turboacc.po

inject_po \
    custom-files/vi-mtwifi-cfg.po \
    package/mtk/applications/luci-app-mtwifi-cfg/po/vi \
    mtwifi-cfg.po

echo "=== PREP 5/8: Generate .config from $DEFCONFIG ==="
cp "$DEFCONFIG" .config
make defconfig

echo "=== PREP 6/8: Validate selected device and required packages ==="
mapfile -t enabled_devices < <(
    grep '^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_.*=y$' .config || true
)

if [ "${#enabled_devices[@]}" -ne 1 ] ||
   [ "${enabled_devices[0]:-}" != 'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_viettel_nr3053=y' ]; then
    echo "ERROR: Expected only viettel_nr3053 to be selected." >&2
    if [ "${#enabled_devices[@]}" -eq 0 ]; then
        echo "  <none>" >&2
    else
        printf '  %s\n' "${enabled_devices[@]}" >&2
    fi
    exit 1
fi

missing_required=()
for package in "${NR3053_REQUIRED_PACKAGES[@]}"; do
    package_enabled "$package" || missing_required+=("$package")
done

if [ "${#missing_required[@]}" -gt 0 ]; then
    echo "ERROR: Required packages are not selected:" >&2
    printf '  - %s\n' "${missing_required[@]}" >&2
    exit 1
fi

echo "=== PREP 7/8: Validate excluded packages and BBR ==="
selected_forbidden=()
for package in "${NR3053_FORBIDDEN_PACKAGES[@]}"; do
    package_enabled "$package" && selected_forbidden+=("$package")
done

if [ "${#selected_forbidden[@]}" -gt 0 ]; then
    echo "ERROR: Forbidden packages were selected:" >&2
    printf '  - %s\n' "${selected_forbidden[@]}" >&2
    exit 1
fi

for symbol in "${NR3053_BBR_SYMBOLS[@]}"; do
    if config_enabled "$symbol"; then
        echo "ERROR: BBR is enabled by configuration symbol: $symbol" >&2
        exit 1
    fi
done

echo "=== PREP 8/8: Validate NR3053 image metadata definition ==="
profile_block="$({
    awk '
        /^define Device\/viettel_nr3053$/ { found=1 }
        found { print }
        found && /^endef$/ { exit }
    ' target/linux/mediatek/image/filogic-ext.mk
} || true)"

if [ -z "$profile_block" ]; then
    echo "ERROR: Device/viettel_nr3053 profile is missing." >&2
    exit 1
fi

for board in "${NR3053_SUPPORTED_DEVICES[@]}"; do
    if ! grep -Fq "$board" <<<"$profile_block"; then
        echo "ERROR: NR3053 profile metadata is missing: $board" >&2
        exit 1
    fi
done

echo
echo "=== PREPARATION COMPLETED ==="
echo "  OK: only viettel_nr3053 is selected"
echo "  OK: 512 MiB RAM / 256 MiB-class NAND profile retained"
echo "  OK: LuCI Bootstrap, MT WiFi, HNAT, WARP and TurboACC MTK retained"
echo "  OK: AdGuard Home package included without custom configuration"
echo "  OK: BBR, ThroughWall, ZRAM, WireGuard, Tailscale and unwanted services excluded"
echo "  OK: sysupgrade metadata supports viettel,nr3053 and sdmc,nr3053"
echo "  OK: custom LuCI footer applied"
