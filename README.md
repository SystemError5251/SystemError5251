# GLITCH BRAWL (Arbeitstitel)

Ein schneller **2D-Multiplayer-Arena-Brawler für Android**: Twin-Stick-Steuerung,
Matches mit 2–3 Minuten Länge, Duell, 3v3 und Jeder gegen jeden. Gespielt wird
im **WLAN mit Freunden** (ein Handy ist Host) oder **online**. Ausgeliefert wird
das Spiel als **APK**.

Das System ist abgestürzt, und abtrünnige Programme wie Firewall, Trojan, Ping,
Patch, Bluescreen und Overclock kämpfen um die letzten freien Ressourcen.

## Status

Konzeptphase. Das vollständige Spielkonzept steht in
**[docs/KONZEPT.md](docs/KONZEPT.md)**: Gameplay, Charaktere, Modi, Arenen,
Technik (Godot 4, Netcode, Backend), APK-Build und -Verteilung sowie Roadmap.

## Geplanter Tech-Stack

| Bereich | Technologie |
|---|---|
| Engine / Client | Godot 4 (GDScript), Android-Export als APK bzw. AAB |
| Multiplayer | Server-autoritativ, ENet (UDP), Client-Vorhersage, LAN-Host-Modus |
| Backend (Online) | Nakama, PostgreSQL, Headless-Godot-Match-Server in Docker |
| CI/CD | GitHub Actions → signiertes APK in GitHub Releases |
