#!/bin/bash
# Build and validate clean ImmortalWrt firmware for Viettel/SDMC NR3053 only.

set -euo pipefail
umask 022
shopt -s nullglob
export LC_ALL=C

DEFCONFIG="${1:-defconfig/nr3053-clean.config}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOBS="${JOBS:-$(nproc)}"
TARGET_DIR="bin/targets/mediatek/filogic"

cd "$REPO_ROOT"

if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: JOBS must be a positive integer; got: $JOBS" >&2
    exit 1
fi

# shellcheck source=scripts/nr3053-package-policy.sh
source scripts/nr3053-package-policy.sh

phase() {
    printf '\n=== %s [%s UTC] ===\n' "$1" "$(date -u +'%Y-%m-%d %H:%M:%S')"
}

phase "BUILD 1/6: Prepare source tree and configuration"
bash scripts/prepare-build.sh "$DEFCONFIG"

phase "BUILD 2/6: Download sources (${JOBS} jobs)"
if ! make -j"$JOBS" download V=s; then
    echo "WARNING: Parallel source download failed; retrying with one job." >&2
    make -j1 download V=s
fi

phase "BUILD 3/6: Compile firmware (${JOBS} jobs)"
if ! make -j"$JOBS" V=sc; then
    echo "WARNING: Parallel build failed; retrying with one job for the exact error." >&2
    make -j1 V=s
fi

phase "BUILD 4/6: Validate package manifest"
mapfile -t manifests < <(compgen -G "$TARGET_DIR/*viettel_nr3053*.manifest" | sort || true)
if [ "${#manifests[@]}" -ne 1 ]; then
    echo "ERROR: Expected exactly one NR3053 manifest; found ${#manifests[@]}." >&2
    if [ "${#manifests[@]}" -eq 0 ]; then
        echo "  <none>" >&2
    else
        printf '  %s\n' "${manifests[@]}" >&2
    fi
    exit 1
fi
manifest="${manifests[0]}"

declare -A manifest_packages=()
while read -r package _; do
    [ -n "$package" ] && manifest_packages["$package"]=1
done < "$manifest"

missing_required=()
for package in "${NR3053_REQUIRED_PACKAGES[@]}"; do
    if [[ ! -v "manifest_packages[$package]" ]]; then
        missing_required+=("$package")
    fi
done
if [ "${#missing_required[@]}" -gt 0 ]; then
    echo "ERROR: Required packages are missing from the image manifest:" >&2
    printf '  - %s\n' "${missing_required[@]}" >&2
    exit 1
fi

selected_forbidden=()
for package in "${NR3053_FORBIDDEN_PACKAGES[@]}"; do
    if [[ -v "manifest_packages[$package]" ]]; then
        selected_forbidden+=("$package")
    fi
done
if [ "${#selected_forbidden[@]}" -gt 0 ]; then
    echo "ERROR: Forbidden packages are present in the image manifest:" >&2
    printf '  - %s\n' "${selected_forbidden[@]}" >&2
    exit 1
fi

phase "BUILD 5/6: Locate and validate firmware images"
require_single_artifact() {
    local pattern="$1"
    local description="$2"
    local matches=()

    mapfile -t matches < <(compgen -G "$TARGET_DIR/$pattern" | sort || true)
    if [ "${#matches[@]}" -ne 1 ]; then
        echo "ERROR: Expected exactly one $description; found ${#matches[@]}." >&2
        if [ "${#matches[@]}" -eq 0 ]; then
            echo "  <none>" >&2
        else
            printf '  %s\n' "${matches[@]}" >&2
        fi
        return 1
    fi

    if [ ! -s "${matches[0]}" ]; then
        echo "ERROR: Artifact is empty: ${matches[0]}" >&2
        return 1
    fi

    printf '%s\n' "${matches[0]}"
}

sysupgrade="$(require_single_artifact '*viettel_nr3053*-sysupgrade.itb' 'sysupgrade image')"
recovery="$(require_single_artifact '*viettel_nr3053*-initramfs-recovery.itb' 'initramfs recovery image')"
fip="$(require_single_artifact '*viettel_nr3053*-bl31-uboot.fip' 'FIP artifact')"
preloader="$(require_single_artifact '*viettel_nr3053*-preloader.bin' 'BL2 preloader artifact')"

fwtool="staging_dir/host/bin/fwtool"
if [ ! -x "$fwtool" ]; then
    echo "ERROR: Host fwtool was not produced: $fwtool" >&2
    exit 1
fi

metadata_file="$(mktemp)"
trap 'rm -f "$metadata_file"' EXIT
"$fwtool" -q -i "$metadata_file" "$sysupgrade"

python3 - "$metadata_file" "${NR3053_SUPPORTED_DEVICES[@]}" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
required = set(sys.argv[2:])

try:
    metadata = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"Invalid sysupgrade metadata: {exc}")

supported = metadata.get("supported_devices")
if not isinstance(supported, list) or not supported:
    supported = metadata.get("new_supported_devices")
if not isinstance(supported, list):
    raise SystemExit("Sysupgrade metadata has no supported-device list")

actual = {str(item) for item in supported}
if actual != required:
    missing = sorted(required - actual)
    extra = sorted(actual - required)
    details = []
    if missing:
        details.append("missing=" + ",".join(missing))
    if extra:
        details.append("unexpected=" + ",".join(extra))
    raise SystemExit("Unexpected sysupgrade supported_devices: " + "; ".join(details))
PY

# FIT generation normally provides dumpimage. Use it as an additional integrity
# check when available, while fwtool metadata validation above remains mandatory.
dumpimage="staging_dir/host/bin/dumpimage"
if [ -x "$dumpimage" ]; then
    "$dumpimage" -l "$sysupgrade" >/dev/null
    "$dumpimage" -l "$recovery" >/dev/null
else
    echo "NOTICE: dumpimage is unavailable; FIT listing check was skipped."
fi

phase "BUILD 6/6: Collect release artifacts and checksums"
rm -rf dist
mkdir -p dist

cp -- "$sysupgrade" "$recovery" "$fip" "$preloader" "$manifest" dist/
(
    cd dist
    sha256sum -- ./* > sha256sums
    sha256sum -c sha256sums
)

echo
echo "=== BUILD COMPLETED SUCCESSFULLY ==="
ls -lh dist/
echo
echo "Normal LuCI/sysupgrade file:"
echo "  dist/$(basename "$sysupgrade")"
echo "Do not flash the preloader or FIP through LuCI/sysupgrade."
