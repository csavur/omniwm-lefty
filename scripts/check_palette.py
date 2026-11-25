#!/usr/bin/env python3
"""Check style.toml basics and apply OmniWM's palette contrast rules to a style folder."""
import re, sys, tomllib
from pathlib import Path

ROLES = ("background surface elevatedSurface foreground secondaryForeground mutedForeground border accent "
         "accentForeground success warning error focus shadow scrim badge red orange yellow green mint teal "
         "cyan blue indigo purple pink brown gray").split()
HUES = ROLES[ROLES.index("red"):]
KEYS = {"format", "name", "version", "api", "minOmniWM", "author", "license", "tags", "title", "summary",
        "description", "previews", "barEffect"}

def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    r, g, b = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)

def main(folder):
    errors = []
    m = tomllib.loads((folder / "style.toml").read_text())
    errors += [f"unknown key {k}" for k in m.keys() - KEYS]
    if m.get("name") != folder.name: errors.append("manifest name must match its folder")
    if m.get("format") != 1 or m.get("api") != 1: errors.append("format and api must be 1")
    if not re.fullmatch(r"(0|[1-9]\d*)(\.(0|[1-9]\d*)){2}", m.get("version", "")): errors.append("bad version")
    errors += [f"missing preview {p}" for p in m.get("previews", []) if not (folder / "previews" / p).is_file()]
    tomllib.loads((folder / "shell.toml").read_text())
    for theme in sorted((folder / "themes").glob("*.toml")):
        data = tomllib.loads(theme.read_text())
        for mode in ("light", "dark"):
            c = data[mode]
            errors += [f"{mode}: missing {r}" for r in ROLES if r not in c]
            def need(a, b, minimum):
                got = contrast(c[a] if a[0] != "#" else a, c[b])
                if got < minimum: errors.append(f"{mode}: {a} on {b} is {got:.2f}, needs {minimum}")
            grounds = ("background", "surface", "elevatedSurface")
            for g in grounds:
                need("foreground", g, 4.5); need("secondaryForeground", g, 4.5)
                for r in HUES + ["accent", "success", "warning", "error", "mutedForeground"]: need(r, g, 3)
            need("accentForeground", "accent", 4.5); need("#FFFFFF", "badge", 3)
    print("\n".join(errors) or f"{folder.name}: ok")
    return 1 if errors else 0

sys.exit(main(Path(sys.argv[1]).resolve()))
