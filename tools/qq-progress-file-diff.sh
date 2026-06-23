#!/usr/bin/env bash
set -euo pipefail

BASE="$HOME/Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac"
OUT="${1:-/tmp/misland-qq-progress-file-diff.txt}"
INTERVAL="${INTERVAL:-6}"

paths=()
while IFS= read -r p; do paths+=("$p"); done < <(
  find "$BASE/iData" "$BASE/mmkv" -maxdepth 1 -type f 2>/dev/null
  printf '%s\n' "$BASE/iLog/QQMusic.mmap3"
  printf '%s\n' "$BASE/iRRCache/rrdbcache.sqlite-wal" "$BASE/iRRCache/rrdbcache.sqlite-shm"
)

snapshot() {
  local label="$1"
  printf '== %s %s ==\n' "$label" "$(date '+%F %T')"
  for p in "${paths[@]}"; do
    [[ -f "$p" ]] || continue
    stat -f '%m %z %N' "$p" | tr '\n' ' '
    shasum -a 256 "$p" | awk '{print $1}'
  done | sort
}

{
  echo "QQ progress file diff"
  echo "interval=${INTERVAL}s"
  snapshot before
  sleep "$INTERVAL"
  snapshot after
} > "$OUT"

echo "$OUT"
