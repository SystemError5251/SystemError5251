#!/usr/bin/env python3
"""Erzeugt alle Pixelart-Assets von GLITCH BRAWL (Charaktere, Kacheln, Schrift, Logo, Icon).

Die Grafiken werden bewusst per Code gezeichnet: Sie sind dadurch reproduzierbar,
lizenzfrei und lassen sich schnell anpassen, solange es noch keine finale Grafik gibt.

Aufruf:  python3 tools/gen_assets.py
Ausgabe: game/assets/...
"""
from __future__ import annotations

import os
import random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets")


def hexc(h: str, a: int = 255) -> tuple[int, int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
OUTLINE = hexc("0b0d14")
WHITE = hexc("f2f5ff")
BG = hexc("0b0f1a")
FLOOR = hexc("141b2d")
FLOOR_EDGE = hexc("19223a")
FLOOR_DOT = hexc("222d4a")
TRACE = hexc("1b3552")
TRACE_NODE = hexc("2a6f8f")
CYAN = hexc("27e1ff")
MAGENTA = hexc("ff3df2")
YELLOW = hexc("ffe14d")
GREEN = hexc("3cff8a")

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------


def new(w: int, h: int, fill=(0, 0, 0, 0)) -> Image.Image:
    return Image.new("RGBA", (w, h), fill)


def rect(img: Image.Image, x0: int, y0: int, x1: int, y1: int, c) -> None:
    """Gefülltes Rechteck, Koordinaten inklusive."""
    for y in range(max(0, y0), min(img.height, y1 + 1)):
        for x in range(max(0, x0), min(img.width, x1 + 1)):
            img.putpixel((x, y), c)


def px(img: Image.Image, x: int, y: int, c) -> None:
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), c)


def outline(img: Image.Image, c=OUTLINE) -> Image.Image:
    """Setzt einen 1-px-Umriss um alle deckenden Pixel."""
    out = img.copy()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            if img.getpixel((x, y))[3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and img.getpixel((nx, ny))[3] > 0:
                    out.putpixel((x, y), c)
                    break
    return out


def shade(c, f: float):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))),
            max(0, min(255, int(c[2] * f))), c[3])


def save(img: Image.Image, *parts: str) -> None:
    path = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


# ---------------------------------------------------------------------------
# Charaktere: 26x30 pro Frame, 6 Frames (2x Idle, 4x Laufen)
# ---------------------------------------------------------------------------
FW, FH = 26, 30
FRAMES = 6


def legs(img, left_x: int, right_x: int, top: int, w: int, col, foot, frame: int) -> None:
    """Zeichnet zwei Beine. Im Lauf-Zyklus wechseln sich die Beine ab."""
    lift = [(0, 0), (0, 0), (-1, 0), (0, 0), (0, -1), (0, 0)][frame]
    for i, (bx, dl) in enumerate(((left_x, lift[0]), (right_x, lift[1]))):
        bottom = FH - 3 + dl
        rect(img, bx, top, bx + w - 1, bottom - 1, col)
        rect(img, bx - (1 if i == 0 else 0), bottom, bx + w - (0 if i == 0 else -1), bottom, foot)


def bob(frame: int) -> int:
    return [0, 1, 0, 1, 0, 1][frame]


def draw_overclock(frame: int) -> Image.Image:
    img = new(FW, FH)
    b = bob(frame)
    body = hexc("6b7590")
    light = hexc("9aa5c4")
    dark = hexc("3e455a")
    legs(img, 8, 15, 22, 3, dark, hexc("2a2f40"), frame)
    # Hitze über dem Chip
    flick = frame % 2
    for x, y in ((8, 4), (12, 3 + flick), (16, 4 - flick)):
        px(img, x, y + b, YELLOW)
        px(img, x, y + 1 + b, hexc("ff9a2e"))
    # Chip-Körper
    rect(img, 5, 6 + b, 20, 21 + b, body)
    rect(img, 5, 6 + b, 20, 6 + b, light)
    rect(img, 5, 6 + b, 5, 21 + b, light)
    rect(img, 6, 21 + b, 20, 21 + b, dark)
    # Pins links/rechts
    for y in (8, 10, 12):
        px(img, 3, y + b, hexc("c8cfdf"))
        px(img, 4, y + b, hexc("c8cfdf"))
        px(img, 21, y + b, hexc("c8cfdf"))
        px(img, 22, y + b, hexc("c8cfdf"))
    # Visier + Augen
    rect(img, 7, 9 + b, 18, 11 + b, hexc("10131d"))
    rect(img, 8, 10 + b, 10, 10 + b, hexc("ff4d4d"))
    rect(img, 15, 10 + b, 17, 10 + b, hexc("ff4d4d"))
    # Blitz auf der Brust
    for x, y in ((13, 13), (12, 14), (11, 15), (12, 15), (13, 15), (14, 15), (13, 16), (12, 17), (11, 18)):
        px(img, x, y + b, YELLOW)
    # Fäuste
    for fx in (0, 20):
        rect(img, fx + 1, 14 + b, fx + 4, 19 + b, hexc("4a5268"))
        rect(img, fx + 1, 14 + b, fx + 4, 14 + b, YELLOW)
        rect(img, fx + 1, 19 + b, fx + 4, 19 + b, hexc("2a2f40"))
    return outline(img)


def draw_ping(frame: int) -> Image.Image:
    img = new(FW, FH)
    b = bob(frame)
    teal = hexc("1f6f6a")
    teal_l = hexc("2fa39a")
    head = hexc("d5def5")
    head_d = hexc("9aa6c8")
    legs(img, 10, 14, 21, 2, hexc("2a3a4a"), hexc("1a2430"), frame)
    # Antenne mit Signal
    rect(img, 12, 2 + b, 12, 5 + b, head_d)
    rect(img, 11, 0 + b, 13, 1 + b, GREEN)
    if frame % 2 == 0:
        px(img, 15, 1 + b, hexc("3cff8a", 160))
        px(img, 16, 2 + b, hexc("3cff8a", 160))
        px(img, 9, 1 + b, hexc("3cff8a", 160))
        px(img, 8, 2 + b, hexc("3cff8a", 160))
    # Kopf
    rect(img, 8, 6 + b, 16, 12 + b, head)
    rect(img, 8, 12 + b, 16, 12 + b, head_d)
    rect(img, 9, 8 + b, 15, 10 + b, hexc("0d2a22"))
    rect(img, 10, 9 + b, 14, 9 + b, GREEN)
    # Körper
    rect(img, 9, 13 + b, 15, 20 + b, teal)
    rect(img, 9, 13 + b, 9, 20 + b, teal_l)
    rect(img, 12, 14 + b, 12, 19 + b, GREEN)
    # Arme + Strahler
    rect(img, 6, 14 + b, 8, 18 + b, teal)
    rect(img, 16, 14 + b, 19, 16 + b, teal)
    rect(img, 20, 13 + b, 22, 17 + b, head_d)
    rect(img, 23, 14 + b, 23, 16 + b, GREEN)
    return outline(img)


def draw_firewall(frame: int) -> Image.Image:
    img = new(FW, FH)
    b = bob(frame)
    brick = hexc("8a3a2e")
    brick_l = hexc("b0503f")
    mortar = hexc("4d1d17")
    legs(img, 7, 15, 23, 4, hexc("3a2420"), hexc("24150f"), frame)
    # Flammen
    rnd = random.Random(frame // 2 * 7 + 3)
    for x in range(5, 21):
        hgt = rnd.randint(1, 4)
        for i in range(hgt):
            col = YELLOW if i == hgt - 1 and hgt > 2 else hexc("ff8a1f") if i > 0 else hexc("ff4d2e")
            px(img, x, 6 - i + b, col)
    # Mauerkörper
    rect(img, 3, 6 + b, 22, 23 + b, brick)
    for row, y in enumerate(range(6, 24, 3)):
        rect(img, 3, y + b, 22, y + b, mortar)
        off = 0 if row % 2 == 0 else 3
        for x in range(3 + off, 23, 6):
            rect(img, x, y + b, x, y + 2 + b, mortar)
    rect(img, 3, 7 + b, 22, 7 + b, brick_l)
    # Sehschlitz
    rect(img, 6, 11 + b, 19, 13 + b, hexc("120806"))
    rect(img, 7, 12 + b, 9, 12 + b, hexc("ffb02e"))
    rect(img, 16, 12 + b, 18, 12 + b, hexc("ffb02e"))
    return outline(img)


def draw_dummy(frame: int) -> Image.Image:
    img = new(FW, FH)
    rect(img, 11, 18, 14, 26, hexc("5a5f75"))
    rect(img, 7, 26, 18, 27, hexc("3a3f55"))
    # Zielscheibe
    for y in range(4, 19):
        for x in range(5, 21):
            d = ((x - 12.5) ** 2 + (y - 11.5) ** 2) ** 0.5
            if d <= 7.5:
                ring = int(d / 2.5)
                px(img, x, y, [hexc("ff4d4d"), WHITE, hexc("ff4d4d"), WHITE][min(ring, 3)])
    return outline(img)


def char_sheet(fn) -> Image.Image:
    sheet = new(FW * FRAMES, FH)
    for f in range(FRAMES):
        sheet.paste(fn(f), (f * FW, 0))
    return sheet


# ---------------------------------------------------------------------------
# Kacheln
# ---------------------------------------------------------------------------
T = 32


def floor_tiles() -> Image.Image:
    """4 Boden-Varianten nebeneinander (128x32)."""
    sheet = new(T * 4, T)
    for v in range(4):
        img = new(T, T, FLOOR)
        rect(img, 0, 0, T - 1, 0, FLOOR_EDGE)
        rect(img, 0, 0, 0, T - 1, FLOOR_EDGE)
        for (x, y) in ((8, 8), (24, 8), (8, 24), (24, 24)):
            px(img, x, y, FLOOR_DOT)
        rnd = random.Random(v * 13 + 1)
        if v >= 1:
            # Leiterbahnen
            y = rnd.choice((6, 12, 20, 26))
            x0, x1 = rnd.randint(0, 10), rnd.randint(18, 31)
            rect(img, x0, y, x1, y, TRACE)
            px(img, x0, y, TRACE_NODE)
            px(img, x1, y, TRACE_NODE)
            if v >= 2:
                x = rnd.choice((6, 14, 22))
                y0, y1 = rnd.randint(0, 8), rnd.randint(20, 31)
                rect(img, x, y0, x, y1, TRACE)
                px(img, x, y1, TRACE_NODE)
        if v == 3:
            rect(img, 13, 13, 18, 18, hexc("1a2440"))
            rect(img, 14, 14, 17, 17, hexc("223056"))
        sheet.paste(img, (v * T, 0))
    return sheet


def wall_tile(variant: int) -> Image.Image:
    """Server-Rack: 32x40 (24 px Oberseite + 16 px Front)."""
    img = new(T, 40)
    top = hexc("2a3352")
    top_l = hexc("3d4a75")
    front = hexc("121729")
    rect(img, 0, 0, T - 1, 23, top)
    rect(img, 0, 0, T - 1, 0, top_l)
    rect(img, 0, 0, 0, 23, top_l)
    rect(img, T - 1, 0, T - 1, 23, hexc("222a45"))
    rect(img, 4, 4, T - 5, 19, hexc("252e4b"))
    rect(img, 6, 6, T - 7, 6, hexc("323d63"))
    rect(img, 0, 24, T - 1, 39, front)
    rect(img, 0, 24, T - 1, 24, hexc("1d2440"))
    rnd = random.Random(variant * 31 + 5)
    for y in (27, 31, 35):
        rect(img, 3, y, T - 4, y + 1, hexc("1a2038"))
        for x in range(5, T - 6, 4):
            if rnd.random() < 0.45:
                px(img, x, y, rnd.choice((GREEN, CYAN, hexc("ffb02e"))))
    rect(img, 0, 39, T - 1, 39, hexc("070910"))
    return img


def block_tile(damaged: bool) -> Image.Image:
    """Zerstörbarer, korrupter Datenblock: 32x40."""
    img = new(T, 40)
    top = hexc("4a2160")
    front = hexc("2a1238")
    rect(img, 1, 1, T - 2, 23, top)
    rect(img, 1, 1, T - 2, 1, hexc("6e3490"))
    rect(img, 1, 24, T - 2, 38, front)
    rnd = random.Random(42 if not damaged else 43)
    for _ in range(26):
        x, y = rnd.randint(3, T - 4), rnd.randint(3, 21)
        rect(img, x, y, x + rnd.randint(0, 3), y, rnd.choice((MAGENTA, hexc("8d3bb5"), CYAN)))
    for y in (28, 33):
        rect(img, 4, y, T - 5, y, hexc("3d1a52"))
    if damaged:
        for (x, y) in ((8, 3), (9, 4), (10, 5), (10, 6), (11, 7), (12, 8), (20, 12), (21, 13), (21, 14),
                       (22, 15), (6, 26), (7, 27), (7, 28), (24, 30), (25, 31)):
            px(img, x, y, OUTLINE)
    return outline(img)


def temp_wall_tile() -> Image.Image:
    """Firewall-Ultimate: leuchtende Energiewand, 32x40."""
    img = new(T, 40)
    rect(img, 1, 2, T - 2, 23, hexc("ff8a1f", 210))
    rect(img, 1, 24, T - 2, 38, hexc("a8500c", 220))
    for y in range(4, 22, 4):
        rect(img, 3, y, T - 4, y, hexc("ffc27a", 230))
    for x in range(4, T - 4, 6):
        rect(img, x, 26, x + 2, 36, hexc("ffe14d", 200))
    return outline(img)


def noise_tiles() -> Image.Image:
    """Rauschen-Feld: 4 Animations-Frames (128x32)."""
    sheet = new(T * 4, T)
    for f in range(4):
        rnd = random.Random(100 + f)
        img = new(T, T, hexc("2a3048", 150))
        for _ in range(140):
            x, y = rnd.randint(0, T - 1), rnd.randint(0, T - 1)
            c = rnd.choice((hexc("6b7194", 190), hexc("9aa0c0", 170), hexc("3a3f5a", 200), hexc("c8ccdf", 120)))
            px(img, x, y, c)
        for _ in range(3):
            y = rnd.randint(0, T - 1)
            rect(img, 0, y, T - 1, y, hexc("8088b0", 90))
        sheet.paste(img, (f * T, 0))
    return sheet


def spawn_pad(col) -> Image.Image:
    img = new(T, T)
    for y in range(T):
        for x in range(T):
            d = ((x - 15.5) ** 2 + (y - 15.5) ** 2) ** 0.5
            if 11 <= d <= 13:
                px(img, x, y, col)
            elif d < 11 and (x + y) % 4 == 0:
                px(img, x, y, shade(col, 0.45))
    return img


# ---------------------------------------------------------------------------
# Power-ups und Projektile
# ---------------------------------------------------------------------------


def pickup_icons() -> Image.Image:
    """3 Icons à 16x16: Backup (Diskette), Cache (Blitz), Overflow (Pfeile)."""
    sheet = new(48, 16)
    # Backup – Diskette
    img = new(16, 16)
    rect(img, 2, 2, 13, 13, hexc("2fbf6a"))
    rect(img, 5, 2, 10, 6, hexc("d5def5"))
    rect(img, 8, 3, 9, 5, hexc("1b6e3d"))
    rect(img, 4, 9, 11, 13, hexc("f2f5ff"))
    rect(img, 5, 10, 10, 10, hexc("9aa6c8"))
    sheet.paste(outline(img), (0, 0))
    # Cache – Blitz
    img = new(16, 16)
    for (x, y) in ((9, 1), (8, 2), (9, 2), (7, 3), (8, 3), (6, 4), (7, 4), (5, 5), (6, 5), (5, 6), (6, 6), (7, 6),
                   (8, 6), (9, 6), (10, 6), (8, 7), (9, 7), (7, 8), (8, 8), (6, 9), (7, 9), (5, 10), (6, 10),
                   (5, 11), (4, 12), (10, 5), (10, 7)):
        px(img, x + 1, y + 1, CYAN)
    sheet.paste(outline(img), (16, 0))
    # Overflow – Doppelpfeil nach oben
    img = new(16, 16)
    for base in (2, 8):
        for i in range(5):
            rect(img, 7 - i, base + i, 8 + i, base + i, hexc("ff4d4d"))
    sheet.paste(outline(img), (32, 0))
    return sheet


def pellet() -> Image.Image:
    img = new(8, 8)
    rect(img, 2, 2, 5, 5, hexc("ffb02e"))
    rect(img, 3, 3, 4, 4, YELLOW)
    return outline(img)


# ---------------------------------------------------------------------------
# Pixel-Schrift (BMFont) – eigene 5x7-Glyphen inkl. Umlaute
# ---------------------------------------------------------------------------
GLYPHS: dict[str, list[str]] = {
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    "Ä": [".#.#.", ".....", ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "Ö": [".#.#.", ".....", ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "Ü": [".#.#.", ".....", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "a": [".....", ".....", ".###.", "....#", ".####", "#...#", ".####"],
    "b": ["#....", "#....", "####.", "#...#", "#...#", "#...#", "####."],
    "c": [".....", ".....", ".####", "#....", "#....", "#....", ".####"],
    "d": ["....#", "....#", ".####", "#...#", "#...#", "#...#", ".####"],
    "e": [".....", ".....", ".###.", "#...#", "#####", "#....", ".####"],
    "f": ["..##", ".#..", "####", ".#..", ".#..", ".#..", ".#.."],
    "g": [".....", ".....", ".####", "#...#", "#...#", "#...#", ".####", "....#", ".###."],
    "h": ["#....", "#....", "####.", "#...#", "#...#", "#...#", "#...#"],
    "i": ["#", ".", "#", "#", "#", "#", "#"],
    "j": ["..#", "...", "..#", "..#", "..#", "..#", "..#", "..#", "##."],
    "k": ["#...", "#...", "#..#", "#.#.", "##..", "#.#.", "#..#"],
    "l": ["#.", "#.", "#.", "#.", "#.", "#.", ".#"],
    "m": [".....", ".....", "####.", "#.#.#", "#.#.#", "#.#.#", "#.#.#"],
    "n": [".....", ".....", "####.", "#...#", "#...#", "#...#", "#...#"],
    "o": [".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###."],
    "p": [".....", ".....", "####.", "#...#", "#...#", "#...#", "####.", "#....", "#...."],
    "q": [".....", ".....", ".####", "#...#", "#...#", "#...#", ".####", "....#", "....#"],
    "r": ["....", "....", "#.##", "##..", "#...", "#...", "#..."],
    "s": [".....", ".....", ".####", "#....", ".###.", "....#", "####."],
    "t": [".#..", ".#..", "####", ".#..", ".#..", ".#..", "..##"],
    "u": [".....", ".....", "#...#", "#...#", "#...#", "#...#", ".####"],
    "v": [".....", ".....", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "w": [".....", ".....", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
    "x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    "y": [".....", ".....", "#...#", "#...#", "#...#", "#...#", ".####", "....#", ".###."],
    "z": [".....", ".....", "#####", "...#.", "..#..", ".#...", "#####"],
    "ä": [".#.#.", ".....", ".###.", "....#", ".####", "#...#", ".####"],
    "ö": [".#.#.", ".....", ".###.", "#...#", "#...#", "#...#", ".###."],
    "ü": [".#.#.", ".....", "#...#", "#...#", "#...#", "#...#", ".####"],
    "ß": [".##..", "#..#.", "#..#.", "#.##.", "#...#", "#...#", "#.##."],
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
    "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
    ".": [".", ".", ".", ".", ".", ".", "#"],
    ",": [".", ".", ".", ".", ".", ".", "#", "#"],
    ":": [".", ".", "#", ".", ".", "#", "."],
    ";": [".", ".", "#", ".", ".", "#", "#"],
    "!": ["#", "#", "#", "#", "#", ".", "#"],
    "?": [".###.", "#...#", "....#", "..##.", "..#..", ".....", "..#.."],
    "-": ["...", "...", "...", "###", "...", "...", "..."],
    "–": ["....", "....", "....", "####", "....", "....", "...."],
    "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
    "/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
    "(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
    ")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
    "[": ["##", "#.", "#.", "#.", "#.", "#.", "##"],
    "]": ["##", ".#", ".#", ".#", ".#", ".#", "##"],
    "%": ["##..#", "##.#.", "...#.", "..#..", ".#...", ".#.##", "#..##"],
    "'": ["#", "#", ".", ".", ".", ".", "."],
    '"': ["#.#", "#.#", "...", "...", "...", "...", "..."],
    "#": [".#.#.", "#####", ".#.#.", ".#.#.", ".#.#.", "#####", ".#.#."],
    "*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
    "=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
    "<": ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"],
    ">": ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."],
    "_": [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
    "&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
    "|": ["#", "#", "#", "#", "#", "#", "#"],
    "→": [".....", "...#.", "....#", "#####", "....#", "...#.", "....."],
    "…": [".....", ".....", ".....", ".....", ".....", ".....", "#.#.#"],
    "·": [".", ".", ".", "#", ".", ".", "."],
    "×": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    "★": ["..#..", "..#..", "#####", ".###.", ".###.", "#...#", "....."],
}

FONT_SIZE = 8   # Nominale Größe: font_size 8 = 1:1, 16 = 2x, 24 = 3x
ACCENT = 2      # Platz über den Großbuchstaben (für Ä, Ö, Ü)
LINE_H = 12
BASE = 7 + ACCENT
# Diese Glyphen beginnen bereits im Akzentbereich (2 Zeilen über der Versalhöhe).
TALL = {"Ä", "Ö", "Ü"}


def build_font() -> None:
    chars = sorted(GLYPHS.keys(), key=ord)
    cell_w, cell_h = 6, 9 + ACCENT
    cols = 16
    rows = (len(chars) + cols - 1) // cols
    img = new(cols * cell_w, rows * cell_h)
    lines = []
    for i, ch in enumerate(chars):
        g = GLYPHS[ch]
        gx, gy = (i % cols) * cell_w, (i // cols) * cell_h
        w = len(g[0])
        top = 0 if ch in TALL else ACCENT
        for y, row in enumerate(g):
            assert len(row) == w, f"Glyph {ch!r}: ungleiche Zeilenbreite"
            for x, c in enumerate(row):
                if c == "#":
                    img.putpixel((gx + x, gy + top + y), (255, 255, 255, 255))
        lines.append(
            f"char id={ord(ch)} x={gx} y={gy} width={w} height={cell_h} xoffset=0 yoffset=0 "
            f"xadvance={w + 1} page=0 chnl=15")
    # Leerzeichen
    lines.append(f"char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=3 page=0 chnl=15")
    save(img, "fonts", "pixel_font.png")
    fnt = [
        f'info face="GlitchPixel" size={FONT_SIZE} bold=0 italic=0 charset="" unicode=1 stretchH=100 '
        f'smooth=0 aa=1 padding=0,0,0,0 spacing=0,0',
        f"common lineHeight={LINE_H} base={BASE} scaleW={img.width} scaleH={img.height} pages=1 packed=0",
        'page id=0 file="pixel_font.png"',
        f"chars count={len(lines)}",
        *lines,
    ]
    with open(os.path.join(OUT, "fonts", "pixel.fnt"), "w", encoding="utf-8") as f:
        f.write("\n".join(fnt) + "\n")


def text_bitmap(text: str) -> Image.Image:
    """Rendert Text mit der Pixel-Schrift (1x) in ein Bild (weiß auf transparent)."""
    w = sum(len(GLYPHS[c][0]) + 1 if c != " " else 3 for c in text)
    img = new(w, 9)
    x = 0
    for c in text:
        if c == " ":
            x += 3
            continue
        g = GLYPHS[c]
        for y, row in enumerate(g):
            for gx, v in enumerate(row):
                if v == "#":
                    img.putpixel((x + gx, y), (255, 255, 255, 255))
        x += len(g[0]) + 1
    return img


def tint(img: Image.Image, c) -> Image.Image:
    out = new(*img.size)
    for y in range(img.height):
        for x in range(img.width):
            if img.getpixel((x, y))[3]:
                out.putpixel((x, y), c)
    return out


def build_logo() -> None:
    """Logo mit RGB-Versatz und Glitch-Streifen.

    Die Schrift wird 2x vergrößert, damit der Farbversatz nur einen halben Glyph-Pixel
    beträgt und das Logo lesbar bleibt (im Spiel nochmals 2x skaliert).
    """
    small = text_bitmap("GLITCH BRAWL")
    base = small.resize((small.width * 2, small.height * 2), Image.NEAREST)
    pad = 4
    w, h = base.width + pad * 2, base.height + pad * 2
    img = new(w, h)
    img.alpha_composite(tint(base, hexc("27e1ff", 220)), (pad - 1, pad))
    img.alpha_composite(tint(base, hexc("ff3df2", 220)), (pad + 1, pad))
    img.alpha_composite(tint(base, WHITE), (pad, pad))
    # Glitch-Streifen: einzelne Zeilen seitlich verschieben
    for row, shift in ((pad + 4, 2), (pad + 9, -2), (pad + 10, -2)):
        line = img.crop((0, row, w, row + 1))
        clear = new(w, 1)
        img.paste(clear, (0, row))
        img.alpha_composite(line, (shift, row))
    save(img, "ui", "logo.png")


def build_icon() -> None:
    """App-Icon 192x192: OVERCLOCK-Kopf auf dunklem Grund mit Neon-Rahmen."""
    s = 192
    img = new(s, s, hexc("0b0f1a"))
    for i in range(6):
        c = hexc("27e1ff") if i < 3 else hexc("ff3df2")
        rect(img, i + 6, 6 + i, s - 7 - i, 6 + i, c if i in (0, 3) else hexc("141b2d"))
    # Rahmen
    for t in range(4):
        rect(img, t, t, s - 1 - t, t, CYAN)
        rect(img, t, s - 1 - t, s - 1 - t, s - 1 - t, MAGENTA)
        rect(img, t, t, t, s - 1 - t, CYAN)
        rect(img, s - 1 - t, t, s - 1 - t, s - 1 - t, MAGENTA)
    char = draw_overclock(0).resize((FW * 6, FH * 6), Image.NEAREST)
    img.alpha_composite(char, ((s - FW * 6) // 2, 10))
    save(img, "..", "icon.png")


def main() -> None:
    random.seed(1)
    save(char_sheet(draw_overclock), "characters", "overclock.png")
    save(char_sheet(draw_ping), "characters", "ping.png")
    save(char_sheet(draw_firewall), "characters", "firewall.png")
    save(char_sheet(draw_dummy), "characters", "dummy.png")
    save(floor_tiles(), "tiles", "floor.png")
    walls = new(T * 3, 40)
    for v in range(3):
        walls.paste(wall_tile(v), (v * T, 0))
    save(walls, "tiles", "wall.png")
    blocks = new(T * 2, 40)
    blocks.paste(block_tile(False), (0, 0))
    blocks.paste(block_tile(True), (T, 0))
    save(blocks, "tiles", "block.png")
    save(temp_wall_tile(), "tiles", "temp_wall.png")
    save(noise_tiles(), "tiles", "noise.png")
    pads = new(T * 2, T)
    pads.paste(spawn_pad(hexc("2d8cff")), (0, 0))
    pads.paste(spawn_pad(hexc("ff8a1f")), (T, 0))
    save(pads, "tiles", "spawn.png")
    save(pickup_icons(), "fx", "pickups.png")
    save(pellet(), "fx", "pellet.png")
    build_font()
    build_logo()
    build_icon()
    print("Assets erzeugt in", OUT)


if __name__ == "__main__":
    main()
