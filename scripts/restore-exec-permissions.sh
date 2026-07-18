#!/bin/bash
# Restore executable bits that can be lost when the source tree is transferred
# through a ZIP archive or edited on Windows.

set -euo pipefail
umask 022

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

python3 - <<'PY'
from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess

root = Path.cwd()

try:
    inside_git = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    ).stdout.strip() == "true"
except FileNotFoundError:
    inside_git = False

if inside_git:
    raw = subprocess.check_output(["git", "ls-files", "-z"])
    paths = [root / os.fsdecode(item) for item in raw.split(b"\0") if item]
else:
    paths = [
        path
        for path in root.rglob("*")
        if path.is_file() and not path.is_symlink() and ".git" not in path.parts
    ]

changed = 0
for path in paths:
    if path.is_symlink() or not path.is_file():
        continue

    try:
        with path.open("rb") as handle:
            if handle.read(2) != b"#!":
                continue

        mode = stat.S_IMODE(path.stat().st_mode)
        new_mode = mode | 0o111
        if new_mode != mode:
            path.chmod(new_mode)
            changed += 1
    except OSError:
        continue

print(f"Restored executable permission on {changed} shebang file(s)")
PY

critical=(
    scripts/feeds
    scripts/install-deps.sh
    scripts/prepare-build.sh
    scripts/build-viettel.sh
    scripts/restore-exec-permissions.sh
    scripts/validate-nr3053-repo.sh
    config/check-uname.sh
    config/check-hostcxx.sh
)

for file in "${critical[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Missing critical executable: $file" >&2
        exit 1
    fi
    chmod +x "$file"
done

echo "OK: executable permissions restored"
