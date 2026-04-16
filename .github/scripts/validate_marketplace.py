#!/usr/bin/env python3
"""Validate marketplace structure, JSON files, and SKILL.md frontmatter."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def validate_json(path: Path) -> dict | list | None:
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as e:
        err(f"{path.relative_to(ROOT)}: invalid JSON — {e}")
        return None


def validate_skill_md(path: Path) -> None:
    text = path.read_text()
    if not text.startswith("---\n"):
        err(f"{path.relative_to(ROOT)}: missing YAML frontmatter")
        return
    end = text.find("\n---\n", 4)
    if end == -1:
        err(f"{path.relative_to(ROOT)}: unterminated frontmatter")
        return
    try:
        meta = yaml.safe_load(text[4:end])
    except yaml.YAMLError as e:
        err(f"{path.relative_to(ROOT)}: invalid YAML frontmatter — {e}")
        return
    if not isinstance(meta, dict):
        err(f"{path.relative_to(ROOT)}: frontmatter is not a mapping")
        return
    for required in ("name", "description"):
        if not meta.get(required):
            err(f"{path.relative_to(ROOT)}: frontmatter missing '{required}'")


def main() -> int:
    # 1. All JSON files parse
    for jp in ROOT.rglob("*.json"):
        if ".git" in jp.parts:
            continue
        validate_json(jp)

    # 2. All SKILL.md files have valid frontmatter
    for sm in ROOT.rglob("SKILL.md"):
        validate_skill_md(sm)

    # 3. Every plugin listed in marketplace.json has a plugin.json on disk
    mp_path = ROOT / ".claude-plugin" / "marketplace.json"
    if mp_path.exists():
        mp = validate_json(mp_path) or {}
        for plugin in mp.get("plugins", []):
            name = plugin.get("name", "?")
            src = plugin.get("source", "")
            if not src.startswith("./"):
                err(f"marketplace.json: plugin '{name}' source must be relative (./...)")
                continue
            plugin_dir = ROOT / src[2:]
            manifest = plugin_dir / ".claude-plugin" / "plugin.json"
            if not manifest.exists():
                err(f"marketplace.json: plugin '{name}' missing manifest at {manifest.relative_to(ROOT)}")
                continue
            manifest_data = validate_json(manifest) or {}
            if manifest_data.get("name") != name:
                err(
                    f"{manifest.relative_to(ROOT)}: name '{manifest_data.get('name')}' "
                    f"does not match marketplace entry '{name}'"
                )

    if errors:
        print("Validation failed:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print("Validation OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
