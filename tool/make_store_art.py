"""Renders the Play Store icon (512x512) and feature graphic (1024x500)."""
import sys
from PIL import Image, ImageDraw, ImageFont

out, font_path = sys.argv[1], sys.argv[2]
BG, ACCENT, FG, MUTED = (15, 20, 25), (78, 154, 241), (230, 237, 243), (120, 134, 150)

def mark(d, x0, y0, scale):
    chevron = [(34, 38), (50, 54), (34, 70), (28.5, 64.5), (39, 54), (28.5, 43.5)]
    d.polygon([(x0 + (x - 18) * scale, y0 + (y - 18) * scale) for x, y in chevron], fill=ACCENT)
    d.rectangle([x0 + 36 * scale, y0 + 46 * scale, x0 + 62 * scale, y0 + 53 * scale], fill=FG)

# 512 icon (Play adds the rounded mask itself)
s = 4
icon = Image.new("RGB", (512 * s, 512 * s), BG)
mark(ImageDraw.Draw(icon), 0, 0, 512 * s / 72)
icon.resize((512, 512), Image.LANCZOS).save(f"{out}/icon-512.png")

# Feature graphic
W, H = 1024 * s, 500 * s
fg = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(fg)
for i in range(0, W, 28 * s):  # faint terminal grid
    d.line([(i, 0), (i, H)], fill=(20, 27, 34), width=s)
mark(d, 70 * s, 110 * s, 280 * s / 72)
title = ImageFont.truetype(font_path, 120 * s)
sub = ImageFont.truetype(font_path, 34 * s)
small = ImageFont.truetype(font_path, 24 * s)
d.text((400 * s, 120 * s), "Nabby", font=title, fill=FG)
d.text((405 * s, 270 * s), "SSH & SFTP client", font=sub, fill=ACCENT)
d.text((405 * s, 320 * s), "Terminal · Files · Keys · Tunnels", font=small, fill=MUTED)
d.text((405 * s, 400 * s), "Edit BY Black Ring Security", font=small, fill=MUTED)
fg.resize((1024, 500), Image.LANCZOS).save(f"{out}/feature-graphic-1024x500.png")
print("ok")
