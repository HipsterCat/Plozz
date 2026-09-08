#!/usr/bin/env bash
#
# prune-deriveddata.sh -- RETIRED production deletion path.
#
# Production invocations without --dry-run refuse before touching any resources,
# even if the old suspension/rollout gates are opened. Age, a missing worktree,
# and an idle process are not owner release evidence.
#
# --dry-run retains the historical preview, NOT an eligible deletion manifest.
# Its old --this, --worktree PATH, --all, --orphans, --stale-days N and
# --module-cache selectors do not authorize cleanup. The preview can create
# temporary guard/selection state; it is not a strictly read-only inventory.
#
# Use tools/apple-build-cleanup.py inventory with supplied owner release records
# for an exact manifest. Apply additionally requires a separately approved
# maintenance window and inherited exclusive lease. Nothing here enables it.
# See docs/apple-maintenance-windows.md.
#
set -euo pipefail

DD="${DERIVED_DATA_DIR:-$HOME/Library/Developer/Xcode/DerivedData}"
ACTIVE_MIN="${ACTIVE_MIN:-15}"                       # skip dirs touched within N min
MODULE_CACHE_LIMIT_GB="${MODULE_CACHE_LIMIT_GB:-10}" # trim ModuleCache above this
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="orphans"
TARGET=""
DRY=0
TRIM_MODULE_CACHE=0
STALE_DAYS="${STALE_DAYS:-0}"                        # >0: also prune idle live worktrees

usage() { sed -n '2,/^set -/ { /^#/p; }' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --this)        MODE="worktree"; TARGET="$PWD" ;;
    --worktree)    MODE="worktree"; TARGET="${2:?--worktree needs a PATH}"; shift ;;
    --all)         MODE="all" ;;
    --orphans)     MODE="orphans" ;;
    --stale-days)  STALE_DAYS="${2:?--stale-days needs a number}"; shift ;;
    --module-cache) TRIM_MODULE_CACHE=1 ;;
    --dry-run)     DRY=1 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [ "$DRY" -ne 1 ] && [ "${APPLE_BUILD_INTERLOCK_TESTING:-}" != "1" ]; then
  echo "REFUSED: broad DerivedData cleanup is retired. Use apple-build-cleanup.py with an approved exact manifest." >&2
  exit 75
fi

[ -d "$DD" ] || { echo "No DerivedData dir at $DD — nothing to do."; exit 0; }

source "$SELF_DIR/lib/apple-build-guard.sh"
APPLE_BUILD_MAINTENANCE_OWNER="cleanup/prune-deriveddata"

# Resolve a real absolute path (worktrees may be symlinked).
realpath_safe() { /usr/bin/python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || echo "$1"; }
[ -n "$TARGET" ] && TARGET="$(realpath_safe "$TARGET")"

workspace_path_of() {  # echo the WorkspacePath recorded inside a DerivedData dir
  /usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$1/info.plist" 2>/dev/null || true
}

dir_recently_active() {  # 0 (true) if modified within ACTIVE_MIN minutes
  [ -n "$(find "$1" -maxdepth 0 -mmin -"$ACTIVE_MIN" 2>/dev/null)" ]
}

# --- idle-worktree detection (for --stale-days) --------------------------------
STALE_REF=""
cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  [ -n "$STALE_REF" ] && rm -f "$STALE_REF"
  if [ "${APPLE_BUILD_LEASE_SIGNALLED:-0}" -eq 1 ] || [ "$status" -ne 0 ]; then
    abandon_maintenance_lock
  elif ! release_maintenance_lock; then
    status=75
  fi
  exit "$status"
}
APPLE_BUILD_LEASE_SIGNALLED=0
trap 'apple_build_lease_signal_exit 129' HUP
trap 'apple_build_lease_signal_exit 130' INT
trap 'apple_build_lease_signal_exit 143' TERM
trap cleanup EXIT
ensure_stale_ref() {  # a marker file stamped exactly STALE_DAYS days ago
  [ -n "$STALE_REF" ] && return
  STALE_REF="$(mktemp -t ddprune)"
  local stamp
  stamp="$(date -v-"${STALE_DAYS}"d +%Y%m%d%H%M.%S 2>/dev/null \
        || date -d "-${STALE_DAYS} days" +%Y%m%d%H%M.%S 2>/dev/null)"
  touch -t "$stamp" "$STALE_REF"
}
worktree_active() {  # 0 (true) if any SOURCE file under $1 is newer than the ref
  local wt="$1"
  [ -d "$wt" ] || return 1
  ensure_stale_ref
  local hit
  hit="$(find "$wt" -type f \
           -not -path '*/.build/*' -not -path '*/.git/*' \
           -not -path '*/DerivedData/*' -not -path '*/.swiftpm/*' \
           -newer "$STALE_REF" -print 2>/dev/null | head -n1)"
  [ -n "$hit" ]
}

human() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

freed=0
deleted=0
remove_dir() {  # $1 = path, $2 = reason
  local d="$1" reason="$2"
  if dir_recently_active "$d"; then
    echo "skip  (active <${ACTIVE_MIN}m)  $(basename "$d")  [$reason]"
    return
  fi
  if [ "$DRY" -ne 1 ] && ! guard_cache_path_for_delete "$d"; then
    destructive_aborted=1
    return
  fi
  local sz; sz="$(human "$d")"
  if [ "$DRY" -eq 1 ]; then
    echo "would delete  $sz  $(basename "$d")  [$reason]"
  else
    if rm -rf "$d"; then
      echo "deleted  $sz  $(basename "$d")  [$reason]"
      deleted=$((deleted+1))
    else
      echo "Failed to delete $d; stopping destructive maintenance." >&2
      destructive_aborted=1
    fi
  fi
}

destructive_aborted=0
if [ "$DRY" -ne 1 ] && ! validate_cache_container "$DD"; then
  exit 75
fi
if [ "$DRY" -ne 1 ] && ! begin_destructive_maintenance; then
  exit 75
fi

shopt -s nullglob
for d in "$DD"/*/; do
  [ "$destructive_aborted" -eq 0 ] || break
  d="${d%/}"
  base="$(basename "$d")"
  case "$base" in
    *.noindex) continue ;;   # ModuleCache/CompilationCache/SDKStatCaches handled separately
  esac
  wp="$(workspace_path_of "$d")"
  case "$MODE" in
    all)
      remove_dir "$d" "all"
      ;;
    orphans)
      if [ -n "$wp" ] && [ ! -e "$wp" ]; then
        remove_dir "$d" "orphan: $wp gone"
      elif [ "$STALE_DAYS" -gt 0 ] && [ -n "$wp" ] && [ -e "$wp" ]; then
        # Worktree still exists — prune only if its source is idle >= STALE_DAYS
        # days (a cold rebuild is the only cost). Source is never touched.
        wtroot="$(dirname "$wp")"
        if ! worktree_active "$wtroot" && ! dir_recently_active "$d"; then
          remove_dir "$d" "stale: idle >=${STALE_DAYS}d ($(basename "$wtroot"))"
        fi
      fi
      ;;
    worktree)
      wpr="$(realpath_safe "$wp")"
      case "$wpr/" in
        "$TARGET"/*) remove_dir "$d" "worktree $TARGET" ;;
      esac
      ;;
  esac
done

if [ "$TRIM_MODULE_CACHE" -eq 1 ] && [ -d "$DD/ModuleCache.noindex" ]; then
  mc_kb="$(du -sk "$DD/ModuleCache.noindex" 2>/dev/null | awk '{print $1}')"
  limit_kb=$(( MODULE_CACHE_LIMIT_GB * 1024 * 1024 ))
  if [ "${mc_kb:-0}" -gt "$limit_kb" ]; then
    [ "$destructive_aborted" -ne 0 ] ||
      remove_dir "$DD/ModuleCache.noindex" "ModuleCache > ${MODULE_CACHE_LIMIT_GB}GB"
  else
    echo "ModuleCache.noindex under ${MODULE_CACHE_LIMIT_GB}GB ($(human "$DD/ModuleCache.noindex")) — kept."
  fi

fi

if [ "$destructive_aborted" -ne 0 ]; then
  echo "Stopped: a build/open-path safety check failed; no further cache paths were deleted."
  exit 75
fi

if [ "$DRY" -eq 1 ]; then
  echo "Dry run — nothing deleted."
else
  echo "Done. Removed $deleted DerivedData folder(s). Remaining: $(human "$DD")."
fi
