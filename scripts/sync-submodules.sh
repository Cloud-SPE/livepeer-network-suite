#!/usr/bin/env bash
# sync-submodules.sh — coordinate submodule pins for the Livepeer Network Suite.
#
# Modes:
#   --check    Report submodules whose checkout differs from the recorded pin.
#              Exits 0 if all match, 1 if any drift, 2 on usage error.
#   --update   For every submodule, fetch and advance to upstream HEAD of its tracked branch.
#              Stages the new pins; does NOT commit.
#   --verify   Pre-release gate: working tree must be clean AND pins must match checkouts.
#   --help     Show this message.

set -euo pipefail

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

require_meta_root() {
  if [ ! -f .gitmodules ]; then
    echo "no .gitmodules at $(pwd) — run from the meta-repo root, or add a submodule first" >&2
    exit 2
  fi
}

list_submodule_paths() {
  git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | awk '{print $2}' || true
}

cmd_check() {
  require_meta_root
  local drift=0 path pinned actual has_head=1
  if ! git rev-parse --verify --quiet HEAD >/dev/null; then
    has_head=0
    echo "note: no commits yet — comparing against staged index instead of HEAD"
  fi
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    if [ ! -e "$path/.git" ]; then
      echo "MISSING $path  (run: git submodule update --init --recursive)"
      drift=1
      continue
    fi
    if [ "$has_head" -eq 1 ]; then
      pinned=$(git ls-tree HEAD -- "$path" 2>/dev/null | awk '{print $3}')
    else
      pinned=$(git ls-files --stage -- "$path" 2>/dev/null | awk '{print $2}')
    fi
    actual=$(git -C "$path" rev-parse HEAD)
    if [ -z "$pinned" ]; then
      echo "UNPINNED $path  actual=$actual  (no recorded pin yet)"
      drift=1
    elif [ "$pinned" != "$actual" ]; then
      echo "DRIFT  $path  pinned=$pinned  actual=$actual"
      drift=1
    else
      echo "OK     $path  $pinned"
    fi
  done < <(list_submodule_paths)
  return $drift
}

cmd_update() {
  require_meta_root
  local path branch
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    branch=$(git config --file .gitmodules "submodule.$path.branch" 2>/dev/null || echo "")
    branch="${branch:-main}"
    echo ">>> advancing $path to upstream $branch"
    git -C "$path" fetch origin "$branch"
    git -C "$path" checkout "$branch"
    git -C "$path" pull --ff-only origin "$branch"
    git add -- "$path"
  done < <(list_submodule_paths)
  echo
  echo "Pin updates staged. Review with 'git diff --cached', then commit."
}

cmd_verify() {
  require_meta_root
  if ! git diff-index --quiet HEAD --; then
    echo "working tree dirty — commit or stash first" >&2
    exit 1
  fi
  cmd_check
}

case "${1:-}" in
  --check)   cmd_check ;;
  --update)  cmd_update ;;
  --verify)  cmd_verify ;;
  --help|"") usage 0 ;;
  *)         echo "unknown mode: $1" >&2; usage 2 ;;
esac
