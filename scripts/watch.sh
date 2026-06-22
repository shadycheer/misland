#!/bin/bash
# Zero-dependency "hot reload": poll source files, and on any change
# rebuild + kill the old instance + relaunch. Run once, leave it running.
cd "$(dirname "$0")/.." || exit 1

echo "👀 watching Sources/ + Resources/ — edits auto rebuild & relaunch (Ctrl-C to stop)"
last=""
while true; do
  cur=$(find Sources Resources -type f \( -name '*.swift' -o -name '*.plist' \) \
        -exec stat -f '%m %N' {} + 2>/dev/null | sort | md5)
  if [ "$cur" != "$last" ]; then
    [ -n "$last" ] && echo "🔁 change detected — rebuilding…"
    last="$cur"
    if make bundle >/tmp/notch-build.log 2>&1; then
      killall NotchIsland 2>/dev/null
      sleep 0.3
      open -n .build/NotchIsland.app
      echo "✅ relaunched at $(date +%H:%M:%S)"
    else
      echo "❌ build failed:"
      grep -E "error:" /tmp/notch-build.log | head -20
    fi
  fi
  sleep 1
done
