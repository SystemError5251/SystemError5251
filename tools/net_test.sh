#!/usr/bin/env bash
# LAN-Test mit zwei echten Spielinstanzen (Host + Client) auf diesem Rechner.
# Beide spielen per Autopilot ein kurzes Match über ENet/UDP.
#
# Aufruf: tools/net_test.sh [matchdauer_s] [lag_ms,verlust_prozent]
#   z. B. tools/net_test.sh 30 50,5   → 100 ms Ping (2 × 50 ms) und 5 % Paketverlust
set -euo pipefail
TIME="${1:-30}"
SIM="${2:-}"
GODOT="${GODOT_BIN:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp -d)"

CLIENT_ARGS=(--net-join=127.0.0.1)
if [[ -n "$SIM" ]]; then
  CLIENT_ARGS+=(--net-sim="$SIM")
fi

"$GODOT" --headless --path "$ROOT/game" -- --net-host="$TIME" > "$LOG/host.log" 2>&1 &
HOST_PID=$!
sleep 2
set +e
timeout $((TIME + 90)) "$GODOT" --headless --path "$ROOT/game" -- "${CLIENT_ARGS[@]}" > "$LOG/client.log" 2>&1
CLIENT_EXIT=$?
wait "$HOST_PID"
HOST_EXIT=$?
set -e

grep -h "NETTEST" "$LOG/host.log" "$LOG/client.log" || true
if [[ $HOST_EXIT -ne 0 || $CLIENT_EXIT -ne 0 ]]; then
  echo "LAN-Test fehlgeschlagen (Host $HOST_EXIT, Client $CLIENT_EXIT). Logs: $LOG" >&2
  grep -h "SCRIPT ERROR\|^ERROR" "$LOG/host.log" "$LOG/client.log" | head -20 >&2 || true
  exit 1
fi
echo "LAN-Test bestanden"
