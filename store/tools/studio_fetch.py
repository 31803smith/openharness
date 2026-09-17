"""Fetch reviewed source pins without installing a service or changing user configuration."""
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
sources = json.loads((root / "upstream.lock.json").read_text())
for source in sources:
    target = root / source["directory"]
    def git(*args):
        return subprocess.check_output(["git", "-C", str(target), *args], text=True,
                                       env={**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"}).strip()
    if not (target / ".git").exists():
        target.mkdir(parents=True, exist_ok=True)
        git("init", "-q")
        git("remote", "add", "origin", source["url"])
        if source.get("sparse"):
            git("sparse-checkout", "init", "--cone")
            git("sparse-checkout", "set", *source["sparse"])
    if git("remote", "get-url", "origin") != source["url"]:
        raise SystemExit(f"Unexpected upstream remote in {target}")
    try:
        current = git("rev-parse", "HEAD")
    except subprocess.CalledProcessError:
        current = ""
    if current != source["commit"]:
        if current and git("status", "--porcelain"):
            raise SystemExit(f"Save your edits in {target} before changing its source pin")
        git("fetch", "--depth", "1", "--filter=blob:none", "origin", source["commit"])
        git("checkout", "--detach", source["commit"])
    print(f'ok {source["name"]} at {source["commit"][:12]}', flush=True)
