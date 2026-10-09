"""Renders the legacy (pre-API 26) launcher PNGs matching the adaptive icon."""
import sys
from PIL import Image, ImageDraw

res = sys.argv[1]
sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for name, size in sizes.items():
    s = 4  # supersample
    W = size * s
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, W - 1], radius=W * 0.22, fill=(15, 20, 25, 255))
    k = W / 72  # map from the 72dp safe zone of the 108dp adaptive canvas
    off = 18
    chevron = [(34, 38), (50, 54), (34, 70), (28.5, 64.5), (39, 54), (28.5, 43.5)]
    d.polygon([((x - off) * k, (y - off) * k) for x, y in chevron], fill=(78, 154, 241, 255))
    d.rectangle([(54 - off) * k, (64 - off) * k, (80 - off) * k, (71 - off) * k], fill=(230, 237, 243, 255))
    img.resize((size, size), Image.LANCZOS).save(f"{res}/mipmap-{name}/ic_launcher.png")
print("ok")
