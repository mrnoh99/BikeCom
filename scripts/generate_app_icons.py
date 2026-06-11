#!/usr/bin/env python3
"""BikeComputer 앱 아이콘(1024×1024) 생성 — iOS · watchOS."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
IOS_ICON = ROOT / "BikeComputer/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
WATCH_ICON = ROOT / "BikeComputerWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

# Theme.swift 토큰
BLACK = (0, 0, 0)
GOLD = (255, 209, 26)
BLUE = (41, 140, 255)
DARK = (28, 28, 30)


def draw_icon(size: int, *, watch: bool = False) -> Image.Image:
    img = Image.new("RGB", (size, size), BLACK)
    draw = ImageDraw.Draw(img)

    cx = cy = size // 2
    scale = size / 1024.0
    wheel_r = int(290 * scale) if not watch else int(310 * scale)
    stroke = max(int(26 * scale), 2)

    # 은은한 원형 배경
    pad = int(48 * scale)
    draw.ellipse([pad, pad, size - pad, size - pad], fill=DARK)

    # 바퀴 외곽(골드)
    draw.ellipse(
        [cx - wheel_r, cy - wheel_r, cx + wheel_r, cy + wheel_r],
        outline=GOLD,
        width=stroke,
    )

    # 스포크
    spoke_len = wheel_r * 0.82
    spoke_w = max(int(9 * scale), 1)
    for i in range(8):
        angle = i * math.pi / 4 - math.pi / 2
        x2 = cx + spoke_len * math.cos(angle)
        y2 = cy + spoke_len * math.sin(angle)
        draw.line([cx, cy, x2, y2], fill=GOLD, width=spoke_w)

    # 허브
    hub = int(52 * scale)
    draw.ellipse([cx - hub, cy - hub, cx + hub, cy + hub], fill=GOLD)

    # 속도 호(블루) — 상단 240° 호
    arc_r = wheel_r + int(36 * scale)
    arc_box = [cx - arc_r, cy - arc_r, cx + arc_r, cy + arc_r]
    draw.arc(arc_box, start=200, end=340, fill=BLUE, width=max(int(18 * scale), 2))

    # 호 끝 점
    for deg in (200, 340):
        rad = math.radians(deg)
        px = cx + arc_r * math.cos(rad)
        py = cy + arc_r * math.sin(rad)
        dot = max(int(14 * scale), 2)
        draw.ellipse([px - dot, py - dot, px + dot, py + dot], fill=BLUE)

    if not watch:
        # iOS: 하단 골드 속도 눈금 3개
        tick_r = wheel_r + int(58 * scale)
        for deg in (110, 90, 70):
            rad = math.radians(deg)
            x1 = cx + (tick_r - int(20 * scale)) * math.cos(rad)
            y1 = cy + (tick_r - int(20 * scale)) * math.sin(rad)
            x2 = cx + tick_r * math.cos(rad)
            y2 = cy + tick_r * math.sin(rad)
            draw.line([x1, y1, x2, y2], fill=GOLD, width=max(int(8 * scale), 1))

    return img


def main() -> None:
    ios = draw_icon(1024, watch=False)
    watch = draw_icon(1024, watch=True)

    IOS_ICON.parent.mkdir(parents=True, exist_ok=True)
    WATCH_ICON.parent.mkdir(parents=True, exist_ok=True)

    ios.save(IOS_ICON, format="PNG", optimize=True)
    watch.save(WATCH_ICON, format="PNG", optimize=True)

    print(f"Wrote {IOS_ICON}")
    print(f"Wrote {WATCH_ICON}")


if __name__ == "__main__":
    main()
