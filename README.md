# GLITCH BRAWL (Arbeitstitel)

Ein schneller **2D-Multiplayer-Arena-Brawler für Android**: Twin-Stick-Steuerung,
Matches mit 2–3 Minuten Länge, Duell, 3v3 und Jeder gegen jeden. Gespielt wird
im **WLAN mit Freunden** (ein Handy ist Host) oder **online**. Ausgeliefert wird
das Spiel als **APK**.

Das System ist abgestürzt, und abtrünnige Programme wie Firewall, Trojan, Ping,
Patch, Bluescreen und Overclock kämpfen um die letzten freien Ressourcen.

![Team-Crash](docs/fortschritt/03-zielvorschau.png)

## Status: spielbarer Prototyp (v0.1.0)

- 3 Charaktere, Team-Crash 3v3, Duell 1v1 und Training gegen Bots
- Touch-Steuerung mit Auto-Aim, Android-APK (arm64, Android 7+)
- Mehrspieler (LAN/online) ist der nächste Schritt

Details mit Bildern und Verbesserungsvorschlägen: **[docs/FORTSCHRITT.md](docs/FORTSCHRITT.md)**
Vollständiges Spielkonzept: **[docs/KONZEPT.md](docs/KONZEPT.md)**

## Projektstruktur

```
game/                  Godot-4.7-Projekt
  scripts/core/        Simulation: Arena, Kämpfer, Match-Regeln, Effekte
  scripts/bots/        Bot-KI und Spieler-Eingabe
  scripts/ui/          Menüs, HUD, Touch-Steuerung
  scripts/data/        Charakter- und Arena-Daten
  tests/               Headless-Tests und Balancing-Simulation
  assets/              Generierte Pixelart, Schrift, Logo
tools/
  gen_assets.py        Erzeugt alle Grafiken per Code
  build_apk.sh         Baut das signierte APK
  screenshots.sh       Automatischer Screenshot-Rundgang
.github/workflows/     CI: Tests + APK bei jedem Push, Release-APK bei Tags v*
docs/                  Konzept und Fortschrittsberichte
```

## Schnellstart

| Aufgabe | Befehl |
|---|---|
| Im Editor öffnen | Godot 4.7 starten → `game/project.godot` importieren |
| Tests | `godot --headless --path game res://tests/test_runner.tscn` |
| Balancing-Simulation | `godot --headless --path game res://tests/balance_sim.tscn -- --duels=20 --teams=24` |
| Debug-APK | `ANDROID_SDK_ROOT=… tools/build_apk.sh debug` → `build/glitch-brawl-0.1.0-debug.apk` |

Auf dem Desktop: Bewegen mit **WASD**, die Touch-Sticks lassen sich mit der Maus bedienen.

## Tech-Stack

| Bereich | Technologie |
|---|---|
| Engine / Client | Godot 4.7 (GDScript, Compatibility-Renderer), Android-Export als APK |
| Multiplayer (geplant) | Server-autoritativ, ENet (UDP), Client-Vorhersage, LAN-Host-Modus |
| Backend (geplant) | Nakama, PostgreSQL, Headless-Godot-Match-Server in Docker |
| CI/CD | GitHub Actions → APK als Build-Artefakt, Release-APK bei Tags |
