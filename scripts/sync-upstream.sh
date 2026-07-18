#!/bin/bash
# Safely merge an upstream ImmortalWrt MT798x branch into this NR3053 fork.
# Usage: bash scripts/sync-upstream.sh [remote] [branch]
# Defaults: remote=upstream, branch=25.12

set -euo pipefail
umask 022

REMOTE="${1:-upstream}"
BRANCH="${2:-25.12}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: This command must run inside a Git work tree." >&2
    exit 1
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "ERROR: Git remote does not exist: $REMOTE" >&2
    echo "Add it first, for example:" >&2
    echo "  git remote add upstream https://github.com/quytttb/immortalwrt-mt798x-rebase.git" >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: Commit or stash local changes before syncing upstream." >&2
    exit 1
fi

echo "Registering the merge=ours driver used by .gitattributes..."
git config merge.ours.driver true

echo "Fetching ${REMOTE}/${BRANCH}..."
git fetch "$REMOTE" "$BRANCH"
upstream_ref="${REMOTE}/${BRANCH}"
upstream_sha="$(git rev-parse --short "$upstream_ref")"

if git merge-base --is-ancestor "$upstream_ref" HEAD; then
    echo "Already up to date with ${upstream_ref} (${upstream_sha})."
    exit 0
fi

echo "Merging ${upstream_ref} (${upstream_sha}) without committing yet..."
if ! git merge --no-ff --no-commit "$upstream_ref"; then
    echo >&2
    echo "ERROR: Merge conflicts remain. Resolve them or run: git merge --abort" >&2
    git diff --name-only --diff-filter=U >&2 || true
    exit 1
fi

unresolved_conflicts="$(git diff --name-only --diff-filter=U)"
if [ -n "$unresolved_conflicts" ]; then
    echo "ERROR: Unresolved merge conflicts remain." >&2
    printf '%s\n' "$unresolved_conflicts" >&2
    exit 1
fi

bash scripts/restore-exec-permissions.sh
if ! bash scripts/validate-nr3053-repo.sh; then
    echo >&2
    echo "ERROR: The merged tree violates NR3053 build rules." >&2
    echo "Fix the reported problem, or abort with: git merge --abort" >&2
    exit 1
fi

git add -A
git commit -m "chore: sync upstream ${BRANCH} (${upstream_sha})"

echo
echo "Sync complete. Review the commit before pushing:"
echo "  git show --stat --oneline HEAD"
echo "  git push origin HEAD"
