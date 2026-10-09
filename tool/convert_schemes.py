"""Converts Tabby's community color schemes (Xresources format) into assets/color_schemes.json."""
import json, os, sys

src, out = sys.argv[1], sys.argv[2]
schemes = [
    {"name": "Tabby Default", "foreground": "#cacaca", "background": "#171717", "cursor": "#bbbbbb",
     "colors": ["#000000", "#ff615a", "#b1e969", "#ebd99c", "#5da9f6", "#e86aff", "#82fff7", "#dedacf",
                "#313131", "#f58c80", "#ddf88f", "#eee5b2", "#a5c7ff", "#ddaaff", "#b7fff9", "#ffffff"]},
    {"name": "Tabby Default Light", "foreground": "#4d4d4c", "background": "#ffffff", "cursor": "#4d4d4c",
     "colors": ["#000000", "#c82829", "#718c00", "#eab700", "#4271ae", "#8959a8", "#3e999f", "#ffffff",
                "#000000", "#c82829", "#718c00", "#eab700", "#4271ae", "#8959a8", "#3e999f", "#ffffff"]},
]
for name in sorted(os.listdir(src), key=str.lower):
    lines = open(os.path.join(src, name), encoding="utf-8").read().split("\n")
    variables, values = {}, {}
    for l in lines:
        if l.startswith("#define"):
            parts = l.split()
            if len(parts) >= 3:
                variables[parts[1]] = parts[2]
    for l in lines:
        if l.startswith("*."):
            k, _, v = l[2:].partition(":")
            v = v.strip()
            values[k.strip()] = variables.get(v, v)
    colors = []
    while f"color{len(colors)}" in values and len(colors) < 16:
        colors.append(values[f"color{len(colors)}"])
    if len(colors) < 16 or "foreground" not in values or "background" not in values:
        continue
    schemes.append({"name": name.strip(), "foreground": values["foreground"], "background": values["background"],
                    "cursor": values.get("cursorColor", values["foreground"]), "colors": colors})
json.dump(schemes, open(out, "w"), separators=(",", ":"))
print(len(schemes))
