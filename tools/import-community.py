#!/usr/bin/env python3
"""Importa al repo los eggs de la comunidad (github.com/pelican-eggs) que aún no tenemos.

Uso:  python3 tools/import-community.py [--dry-run]

- Prefiere el formato Pterodactyl (egg-pterodactyl-*.json, el del repo); si una carpeta
  solo tiene formato Pelican lo convierte lo justo (startup_commands -> startup).
- Se salta los eggs cuyo nombre ya existe en el repo (sin distinguir mayúsculas/símbolos).
- Pone uuid estable (el mismo que generaría el panel), update_url propio y sustituye las
  menciones de Pelican/Pterodactyl en textos visibles por cinammon.net (no en URLs,
  imágenes Docker ni scripts, que son funcionales).
- Después ejecuta tools/embed-icons.py para los iconos.
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "cinammon-eggs-import/1.0"}

# Nombres de la comunidad que son el mismo egg que uno nuestro con otro nombre.
DUPLICATES = {"mohistmc", "waterdog"}

# repo de la comunidad -> carpeta/categoría del repo de cinammon
REPOS = {
    "pelican-eggs/games-steamcmd": "games",
    "pelican-eggs/games-standalone": "games",
    "pelican-eggs/minecraft": "minecraft",
    "pelican-eggs/chatbots": "bots",
    "pelican-eggs/database": "database",
    "pelican-eggs/generic": "generic",
    "pelican-eggs/software": "software",
    "pelican-eggs/monitoring": "software",
    "pelican-eggs/storage": "software",
    "pelican-eggs/voice": "voice",
}


def get(url: str) -> bytes:
    headers = dict(UA)
    # Opcional: GITHUB_TOKEN evita el límite de 60 consultas/hora de la API sin autenticar.
    if os.environ.get("GITHUB_TOKEN") and url.startswith("https://api.github.com/"):
        headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
        return r.read()


def norm(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def slug(name: str) -> str:
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", name.lower())).strip("-") or "egg"


def rebrand(text: str) -> str:
    text = re.sub(r"\bfor (the )?(Pelican|Pterodactyl)( Panel)?\b", "for cinammon.net", text, flags=re.I)
    return re.sub(r"\b(Pelican|Pterodactyl)( Panel)?\b", "cinammon.net", text, flags=re.I)


def existing_names() -> set:
    names = set()
    for cat in os.listdir(ROOT):
        folder = os.path.join(ROOT, cat)
        if cat in ("tools", "docs") or cat.startswith(".") or not os.path.isdir(folder):
            continue
        for f in os.listdir(folder):
            if f.endswith(".json"):
                with open(os.path.join(folder, f), encoding="utf-8") as fh:
                    names.add(norm(json.load(fh).get("name", "")))
    return names


def pick_files(tree: list) -> list:
    """Un archivo por carpeta: el formato Pterodactyl si existe, si no el de Pelican."""
    by_dir: dict = {}
    for item in tree:
        path = item["path"]
        base = path.rsplit("/", 1)[-1]
        if item["type"] != "blob" or not base.startswith("egg-") or not base.endswith(".json"):
            continue
        d = path.rsplit("/", 1)[0] if "/" in path else ""
        by_dir.setdefault(d, []).append(path)
    picked = []
    for paths in by_dir.values():
        ptero = [p for p in paths if p.rsplit("/", 1)[-1].startswith("egg-pterodactyl-")]
        picked.extend(ptero if ptero else paths)
    return sorted(picked)


def main() -> int:
    dry = "--dry-run" in sys.argv
    have = existing_names()
    added, skipped, failed = [], 0, []

    for repo, category in REPOS.items():
        info = json.loads(get(f"https://api.github.com/repos/{repo}"))
        branch = info["default_branch"]
        tree = json.loads(get(f"https://api.github.com/repos/{repo}/git/trees/{branch}?recursive=1"))["tree"]
        for path in pick_files(tree):
            try:
                egg = json.loads(get(f"https://raw.githubusercontent.com/{repo}/{branch}/{urllib.parse.quote(path)}"))
            except Exception as exc:  # noqa: BLE001
                failed.append(f"{repo}/{path}: {exc}")
                continue
            name = (egg.get("name") or "").strip()
            if not name or norm(name) in have or norm(name) in DUPLICATES:
                skipped += 1
                continue

            if not egg.get("startup") and isinstance(egg.get("startup_commands"), dict) and egg["startup_commands"]:
                egg["startup"] = next(iter(egg["startup_commands"].values()))
            egg.pop("startup_commands", None)

            folder = os.path.join(ROOT, category)
            filename = f"egg-{slug(name)}.json"
            n = 2
            while os.path.exists(os.path.join(folder, filename)):
                filename = f"egg-{slug(name)}-{n}.json"
                n += 1

            meta = egg.get("meta") if isinstance(egg.get("meta"), dict) else {}
            out = {
                "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY FOR CINAMMON.NET",
                "meta": {
                    "version": meta.get("version", "PTDL_v2"),
                    "update_url": f"https://raw.githubusercontent.com/cinammon-net/eggs/main/{category}/{filename}",
                },
                # Mismo uuid que generaría el panel al importarlo sin uuid.
                "uuid": str(uuid.uuid5(uuid.NAMESPACE_URL, "cinammon-egg:" + name.lower())),
            }
            for key, value in egg.items():
                if key in ("_comment", "meta", "uuid"):
                    continue
                out[key] = value
            out["description"] = rebrand(out.get("description") or "")
            for var in out.get("variables") or []:
                if isinstance(var, dict) and isinstance(var.get("description"), str):
                    var["description"] = rebrand(var["description"])

            have.add(norm(name))
            added.append(f"{category}/{filename}  ({name})")
            if not dry:
                os.makedirs(folder, exist_ok=True)
                with open(os.path.join(folder, filename), "w", encoding="utf-8") as fh:
                    json.dump(out, fh, indent=4, ensure_ascii=False)
                    fh.write("\n")

    print(f"{len(added)} eggs nuevos, {skipped} ya existían")
    for line in added:
        print("  +", line)
    for line in failed:
        print("  ! fallo:", line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
