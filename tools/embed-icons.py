#!/usr/bin/env python3
"""Incrusta el icono de cada egg en su campo `image` (data URI PNG 128x128).

Uso:  python3 tools/embed-icons.py [--force] [--sheet salida.png]

- Lee las fuentes de tools/icons.json (steam:<appid> | github:<org> | url:<...> | minecraft).
- Sin --force no toca los eggs que ya tienen `image`.
- Requiere Pillow (pip install pillow).
"""
import base64
import glob
import io
import json
import os
import sys
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 128
UA = {"User-Agent": "cinammon-eggs-icons/1.0"}
MINECRAFT = "https://minecraft.wiki/images/Grass_Block_JE7_BE6.png"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def resolve(source: str) -> str:
    kind, _, value = source.partition(":")
    if kind == "steam":
        info = json.loads(fetch(f"https://api.steamcmd.net/v1/info/{value}"))
        icon = info["data"][value]["common"].get("clienticon")
        if not icon:
            raise RuntimeError("sin clienticon")
        return f"https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/{value}/{icon}.ico"
    if kind == "github":
        return f"https://github.com/{value}.png?size={SIZE * 2}"
    if kind == "url":
        return value
    if source == "minecraft":
        return MINECRAFT
    raise RuntimeError(f"fuente desconocida: {source}")


def to_data_uri(raw: bytes) -> str:
    im = Image.open(io.BytesIO(raw))
    if im.format == "ICO":
        im.size = max(im.info["sizes"])
    im = im.convert("RGBA")
    # Recorta a cuadrado centrado y escala.
    w, h = im.size
    side = min(w, h)
    im = im.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2))
    im = im.resize((SIZE, SIZE), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def main() -> int:
    force = "--force" in sys.argv
    sheet = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
    sources = json.load(open(os.path.join(ROOT, "tools", "icons.json")))
    done, failed, tiles = 0, [], []

    for path in sorted(glob.glob(os.path.join(ROOT, "*", "*.json"))):
        with open(path, encoding="utf-8") as fh:
            egg = json.load(fh)
        name = egg.get("name")
        rel = os.path.relpath(path, ROOT)
        if rel.startswith("tools" + os.sep):
            continue

        if egg.get("image") and not force:
            tiles.append((name, egg["image"]))
            continue
        source = sources.get(name)
        if not source:
            failed.append(f"{rel}: sin fuente (usa el icono de categoría)")
            continue
        try:
            egg["image"] = to_data_uri(fetch(resolve(source)))
        except Exception as exc:  # noqa: BLE001
            failed.append(f"{rel}: {source} -> {exc}")
            continue

        with open(path, "w", encoding="utf-8") as fh:
            json.dump(egg, fh, indent=4, ensure_ascii=False)
            fh.write("\n")
        tiles.append((name, egg["image"]))
        done += 1

    print(f"{done} iconos incrustados")
    for line in failed:
        print("  omitido:", line)

    if sheet and tiles:
        cols = 12
        rows = (len(tiles) + cols - 1) // cols
        out = Image.new("RGBA", (cols * 72, rows * 72), (40, 40, 40, 255))
        for i, (_, uri) in enumerate(tiles):
            im = Image.open(io.BytesIO(base64.b64decode(uri.split(",", 1)[1]))).convert("RGBA").resize((64, 64))
            out.paste(im, ((i % cols) * 72 + 4, (i // cols) * 72 + 4), im)
        out.save(sheet)
        print("hoja de contacto:", sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
