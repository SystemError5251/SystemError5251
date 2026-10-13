#!/usr/bin/env bash
# Erzeugt Screenshots per automatischem Rundgang (benötigt Xvfb + Mesa unter Linux).
# Aufruf: tools/screenshots.sh <ausgabeordner>
set -euo pipefail
OUT="${1:-build/screenshots}"
GODOT="${GODOT_BIN:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
xvfb-run -a -s "-screen 0 2400x1200x24" "$GODOT" --path "$ROOT/game" --rendering-driver opengl3 \
  --resolution 1280x720 -- --tour="$OUT"
xvfb-run -a -s "-screen 0 2400x1200x24" "$GODOT" --path "$ROOT/game" --rendering-driver opengl3 \
  --resolution 1600x720 -- --tour="$OUT" --tour-wide
echo "Screenshots in $OUT"
