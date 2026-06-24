#!/bin/bash
# Local development watch: poll source files, debug-build the app bundle, and
# relaunch it on every change. This uses SwiftPM's incremental debug build,
# which is much faster than the release bundle used for packaging.
cd "$(dirname "$0")/.." || exit 1

echo "watching Sources/ + Resources/ -- debug rebuild & relaunch (Ctrl-C to stop)"
last=""
while true; do
  cur=$(find Sources Resources -type f \( -name '*.swift' -o -name '*.plist' \) \
        -exec stat -f '%m %N' {} + 2>/dev/null | sort | md5)
  if [ "$cur" != "$last" ]; then
    [ -n "$last" ] && echo "change detected -- rebuilding debug bundle..."
    last="$cur"
    if make dev-bundle >/tmp/notch-build.log 2>&1; then
      killall misland 2>/dev/null
      sleep 0.2
      open -n .build/misland-dev.app
      echo "relaunched at $(date +%H:%M:%S)"
    else
      echo "build failed:"
      grep -E "error:" /tmp/notch-build.log | head -20
    fi
  fi
  sleep 1
done
