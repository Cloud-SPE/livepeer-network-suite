#!/usr/bin/env bash
# sync-submodules.sh — coordinate submodule pins for the Livepeer Network Suite.
#
# Modes:
#   --check                  Report submodules whose checkout differs from the
#                            recorded pin. Exits 0 if all match, 1 if any drift.
#   --list-updates           Fetch each submodule's origin and categorize the
#                            current pin: up-to-date, new-tag-available,
#                            commits-past-tag, head-pinned-and-advanced,
#                            head-pinned-no-tag, untagged-pin-with-tags-available.
#                            Read-only — does not stage or commit.
#   --update-to-latest-tags  For each submodule with a stable upstream tag past
#                            the current pin, check out that tag and stage.
#                            Skips submodules with no tags or where the tag
#                            isn't a forward-only advance. Does NOT commit.
#   --update-to-head         For every submodule, advance to upstream HEAD of
#                            its tracked branch. WARNING: ignores tags. Stages
#                            the new pins; does NOT commit.
#   --update                 DEPRECATED alias for --update-to-head; warns on use.
#   --verify                 Pre-release gate: working tree must be clean AND
#                            pins must match checkouts.
#   --help                   Show this message.

set -euo pipefail

usage() {
  sed -n '2,23p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

require_meta_root() {
  if [ ! -f .gitmodules ]; then
    echo "no .gitmodules at $(pwd) — run from the meta-repo root" >&2
    exit 2
  fi
}

list_submodule_paths() {
  git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | awk '{print $2}' || true
}

submodule_branch() {
  local path="$1" branch
  branch=$(git config --file .gitmodules "submodule.$path.branch" 2>/dev/null || echo "")
  echo "${branch:-main}"
}

# Returns the stable-tag name (vX.Y.Z) if the given commit is exactly that tag.
# Empty otherwise. "Stable" excludes -rc / -beta / non-semver tags.
tag_for_commit() {
  local repo="$1" commit="$2" tag
  tag=$(git -C "$repo" describe --tags --exact-match "$commit" 2>/dev/null || echo "")
  if [ -n "$tag" ] && printf '%s' "$tag" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "$tag"
  fi
}

# Returns the latest stable tag (vX.Y.Z) in the submodule, or empty if none.
# `|| true` on the pipeline because `grep` exits 1 on no match (under pipefail).
latest_stable_tag() {
  local repo="$1"
  { git -C "$repo" tag --list --sort=-version:refname 2>/dev/null \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
    | head -1 ; } || true
}

# Reads the recorded pin SHA for a submodule path (HEAD if commits exist,
# else the staged index).
recorded_pin() {
  local path="$1" pinned
  if git rev-parse --verify --quiet HEAD >/dev/null; then
    pinned=$(git ls-tree HEAD -- "$path" 2>/dev/null | awk '{print $3}')
  else
    pinned=$(git ls-files --stage -- "$path" 2>/dev/null | awk '{print $2}')
  fi
  echo "$pinned"
}

cmd_check() {
  require_meta_root
  local drift=0 path pinned actual
  if ! git rev-parse --verify --quiet HEAD >/dev/null; then
    echo "note: no commits yet — comparing against staged index instead of HEAD"
  fi
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    if [ ! -e "$path/.git" ]; then
      echo "MISSING $path  (run: git submodule update --init --recursive)"
      drift=1
      continue
    fi
    pinned=$(recorded_pin "$path")
    actual=$(git -C "$path" rev-parse HEAD)
    if [ -z "$pinned" ]; then
      echo "UNPINNED $path  actual=$actual"
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

cmd_list_updates() {
  require_meta_root
  local path branch pinned current_tag latest_tag upstream_head
  local distance_to_head pin_label target_label status detail

  echo "Fetching tags + branches from each submodule's origin..."
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ ! -e "$path/.git" ] && continue
    branch=$(submodule_branch "$path")
    git -C "$path" fetch --quiet --tags origin "$branch" 2>/dev/null || true
  done < <(list_submodule_paths)
  echo

  printf '%-32s  %-16s  %-22s  %s\n' 'SUBMODULE' 'CURRENT PIN' 'LATEST UPSTREAM' 'STATUS'
  printf '%-32s  %-16s  %-22s  %s\n' '---------' '-----------' '---------------' '------'

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    if [ ! -e "$path/.git" ]; then
      printf '%-32s  %s\n' "$path" 'MISSING — run: git submodule update --init'
      continue
    fi
    pinned=$(recorded_pin "$path")
    branch=$(submodule_branch "$path")
    upstream_head=$(git -C "$path" rev-parse "origin/$branch" 2>/dev/null || echo "")
    current_tag=$(tag_for_commit "$path" "$pinned")
    latest_tag=$(latest_stable_tag "$path")

    if [ -n "$current_tag" ]; then
      pin_label="$current_tag"
    else
      pin_label="${pinned:0:7} (no tag)"
    fi

    distance_to_head=0
    if [ -n "$upstream_head" ] && [ "$upstream_head" != "$pinned" ]; then
      distance_to_head=$(git -C "$path" rev-list --count "$pinned..$upstream_head" 2>/dev/null || echo "?")
    fi

    if [ -z "$latest_tag" ]; then
      if [ "$distance_to_head" = "0" ]; then
        status="head-pinned-no-tag"
        detail="no upstream tag; at HEAD"
        target_label="(no tag, at HEAD)"
      else
        status="head-pinned-and-advanced"
        detail="upstream +$distance_to_head past pin; still no tag"
        target_label="${upstream_head:0:7} (+$distance_to_head)"
      fi
    elif [ -n "$current_tag" ]; then
      if [ "$current_tag" = "$latest_tag" ]; then
        if [ "$distance_to_head" = "0" ]; then
          status="up-to-date"
          detail="on latest stable tag"
          target_label="$latest_tag"
        else
          status="commits-past-tag"
          detail="upstream +$distance_to_head past $latest_tag (no newer tag)"
          target_label="$latest_tag (+$distance_to_head)"
        fi
      else
        status="new-tag-available"
        detail="newer stable tag: $current_tag → $latest_tag"
        target_label="$latest_tag"
      fi
    else
      status="untagged-pin-with-tags-available"
      detail="latest stable tag is $latest_tag — consider tag-pinning"
      target_label="$latest_tag"
    fi

    printf '%-32s  %-16s  %-22s  %s — %s\n' \
      "$path" "$pin_label" "$target_label" "$status" "$detail"
  done < <(list_submodule_paths)

  echo
  echo "Status meanings:"
  echo "  up-to-date                          → no action"
  echo "  new-tag-available                   → audit upstream changelog; advance if compatible"
  echo "  commits-past-tag                    → stay unless commits include a critical fix"
  echo "  head-pinned-and-advanced            → advance if commits relevant; ask upstream to tag"
  echo "  head-pinned-no-tag                  → no movement; consider asking upstream to tag a release"
  echo "  untagged-pin-with-tags-available    → consider re-pinning to a tag for stability"
}

cmd_update_to_latest_tags() {
  require_meta_root
  local path pinned latest_tag tag_sha advanced=0

  echo "Fetching tags from each submodule's origin..."
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ ! -e "$path/.git" ] && continue
    git -C "$path" fetch --quiet --tags origin 2>/dev/null || true
  done < <(list_submodule_paths)
  echo

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    if [ ! -e "$path/.git" ]; then
      echo "skip   $path  (missing — run git submodule update --init)"
      continue
    fi
    pinned=$(recorded_pin "$path")
    latest_tag=$(latest_stable_tag "$path")
    if [ -z "$latest_tag" ]; then
      echo "skip   $path  (no stable upstream tag)"
      continue
    fi
    tag_sha=$(git -C "$path" rev-parse "$latest_tag^{commit}" 2>/dev/null || echo "")
    if [ -z "$tag_sha" ]; then
      echo "skip   $path  (could not resolve $latest_tag)"
      continue
    fi
    if [ "$pinned" = "$tag_sha" ]; then
      echo "ok     $path  already at $latest_tag"
      continue
    fi
    if ! git -C "$path" merge-base --is-ancestor "$pinned" "$tag_sha" 2>/dev/null; then
      echo "skip   $path  $latest_tag is NOT a forward-only advance from current pin (manual review)"
      continue
    fi
    echo ">>>>>  $path  advancing to $latest_tag"
    git -C "$path" checkout --quiet "$latest_tag"
    git add -- "$path"
    advanced=$((advanced + 1))
  done < <(list_submodule_paths)

  echo
  if [ "$advanced" -gt 0 ]; then
    echo "$advanced submodule(s) staged. Review with 'git diff --cached', then commit."
  else
    echo "Nothing to update."
  fi
}

cmd_update_to_head() {
  require_meta_root
  echo "WARNING: --update-to-head ignores release tags. Prefer --update-to-latest-tags." >&2
  local path branch
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    branch=$(submodule_branch "$path")
    echo ">>> advancing $path to upstream $branch HEAD"
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
  --check)                   cmd_check ;;
  --list-updates)            cmd_list_updates ;;
  --update-to-latest-tags)   cmd_update_to_latest_tags ;;
  --update-to-head)          cmd_update_to_head ;;
  --update)
    echo "WARNING: --update is deprecated; use --update-to-head explicitly" >&2
    cmd_update_to_head ;;
  --verify)                  cmd_verify ;;
  --help|"")                 usage 0 ;;
  *)                         echo "unknown mode: $1" >&2; usage 2 ;;
esac
