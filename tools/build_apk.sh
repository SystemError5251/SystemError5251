#!/usr/bin/env bash
# Baut das Android-APK mit Godot (ohne Gradle, über die offiziellen Export-Vorlagen).
#
# Aufruf:  tools/build_apk.sh [debug|release]
#
# Benötigt:
#   GODOT_BIN         Godot 4.7.x Editor (Standard: "godot" im PATH) + installierte Export-Vorlagen
#   ANDROID_SDK_ROOT  Android-SDK mit build-tools/<version>/apksigner und platform-tools/adb
#   JAVA_HOME         JDK 17 oder neuer (Standard: aus "java" im PATH ermittelt)
# Nur für Release:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH, GODOT_ANDROID_KEYSTORE_RELEASE_USER,
#   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
set -euo pipefail

MODE="${1:-debug}"
GODOT="${GODOT_BIN:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
JAVA="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"

if [[ "$MODE" != "debug" && "$MODE" != "release" ]]; then
  echo "Modus muss 'debug' oder 'release' sein" >&2
  exit 2
fi
if [[ -z "$SDK" ]]; then
  echo "ANDROID_SDK_ROOT ist nicht gesetzt" >&2
  exit 2
fi
mkdir -p "$OUT"

# 1) Projekt importieren (legt auch die Editor-Einstellungen an)
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true

# 2) SDK- und JDK-Pfad in die Editor-Einstellungen eintragen
SETTINGS="$(ls -t "$HOME"/.config/godot/editor_settings-4*.tres 2>/dev/null | head -1 || true)"
if [[ -z "$SETTINGS" ]]; then
  echo "Godot-Editor-Einstellungen nicht gefunden" >&2
  exit 1
fi
python3 - "$SETTINGS" "$SDK" "$JAVA" <<'PY'
import re, sys
path, sdk, java = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
for key, value in (("export/android/android_sdk_path", sdk), ("export/android/java_sdk_path", java)):
    line = f'{key} = "{value}"'
    if re.search(rf"^{re.escape(key)} = .*$", text, flags=re.M):
        text = re.sub(rf"^{re.escape(key)} = .*$", line, text, flags=re.M)
    else:
        text = text.replace("[resource]\n", f"[resource]\n{line}\n", 1)
open(path, "w", encoding="utf-8").write(text)
PY

# 3) Debug-Schlüssel erzeugen, falls keiner vorgegeben ist
if [[ "$MODE" == "debug" && -z "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-}" ]]; then
  KS="$OUT/debug.keystore"
  if [[ ! -f "$KS" ]]; then
    "$JAVA/bin/keytool" -genkeypair -keystore "$KS" -storepass android -keypass android \
      -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
      -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
  fi
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KS"
  export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
  export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"
fi

# 4) Exportieren
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/game/project.godot")"
APK="$OUT/glitch-brawl-$VERSION-$MODE.apk"
rm -f "$APK"
"$GODOT" --headless --path "$ROOT/game" "--export-$MODE" "Android" "$APK"
if [[ ! -f "$APK" ]]; then
  echo "Export fehlgeschlagen – kein APK erzeugt" >&2
  exit 1
fi

# 5) Signatur prüfen
APKSIGNER="$(ls -d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
"$APKSIGNER" verify --verbose "$APK" | head -5
ls -lh "$APK"
echo "APK: $APK"
