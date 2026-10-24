#!/usr/bin/env python3
"""Project-local Blender runner. No Blender add-on or external MCP needed."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def blender_path():
    candidates = [
        os.environ.get("BLENDER_BIN"),
        ROOT / ".local/Blender.app/Contents/MacOS/Blender",
        "/Applications/Blender.app/Contents/MacOS/Blender",
        shutil.which("blender"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    sys.exit("Blender ausente. Defina BLENDER_BIN ou instale em .local/Blender.app.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["doctor", "smoke", "weapons", "zombies"])
    args = parser.parse_args()
    blender = blender_path()
    if args.command == "doctor":
        print("Blender:", blender, flush=True)
        subprocess.run([blender, "--background", "--factory-startup", "--version"], check=True)
        for tool in ["rojo", "stylua", "selene"]:
            executable = shutil.which(tool)
            if not executable:
                sys.exit("Ferramenta ausente: " + tool)
            subprocess.run([executable, "--version"], check=True)
    else:
        script = {"smoke": "smoke.py", "weapons": "weapons.py", "zombies": "zombies.py"}[args.command]
        subprocess.run([
            blender, "--background", "--factory-startup", "--python-exit-code", "1",
            "--python", str(ROOT / "tools/blender" / script),
            "--", str(ROOT),
        ], check=True, cwd=ROOT)


if __name__ == "__main__":
    main()
