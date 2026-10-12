#!/usr/bin/env python3
"""Bump pkgs/sources/<name>.json to the latest upstream release.

Usage: scripts/update.py [--force] [--check] [NAME ...]

With no NAME, updates craft-fonts and every app. Apps track their newest
`vX.Y.Z` tag; craft-fonts has no tags and tracks the default branch. For each
bump the source hash comes from `nix flake prefetch` and the cargoHash from
building only the app's `cargoDeps` with a fake hash. Prints one
`name: old -> new` line per bump, and exits non-zero if any update failed (a
failed update leaves that name's JSON untouched).

With --check, only prints the names of apps that have a newer release, without
prefetching or writing anything (craft-fonts is skipped).
"""

import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "pkgs" / "sources"
OWNER = "storytold"
TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, cwd=ROOT).stdout


def ls_remote(repo, *args):
    out = run("git", "ls-remote", *args, f"https://github.com/{OWNER}/{repo}")
    return [line.split("\t") for line in out.splitlines()]


def latest_tag(repo):
    tags = [
        ref.removeprefix("refs/tags/")
        for _, ref in ls_remote(repo, "--tags", "--refs")
    ]
    releases = [(tuple(map(int, m.groups())), t) for t in tags if (m := TAG_RE.match(t))]
    if not releases:
        raise RuntimeError(f"{repo}: no vX.Y.Z tags")
    return max(releases)[1]


def prefetch(repo, ref):
    info = json.loads(run("nix", "flake", "prefetch", "--json", f"github:{OWNER}/{repo}/{ref}"))
    date = datetime.fromtimestamp(info["locked"]["lastModified"], timezone.utc).strftime("%Y-%m-%d")
    return info["hash"], date


def cargo_hash(name):
    proc = subprocess.run(
        ["nix", "build", "--no-link", f".#{name}.cargoDeps"],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    if m := re.search(r"got:\s+(sha256-\S+)", proc.stderr):
        return m.group(1)
    raise RuntimeError(f"{name}: no cargoHash mismatch reported\n{proc.stderr[-3000:]}")


def write(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def update_fonts(path, old, force):
    rev = next(sha for sha, ref in ls_remote("craft-fonts") if ref == "HEAD")
    if rev == old.get("rev") and not force:
        return None
    hash_, date = prefetch("craft-fonts", rev)
    new = {"version": f"0-unstable-{date}", "rev": rev, "hash": hash_}
    write(path, new)
    return f"{old.get('rev', '?')[:8]} -> {rev[:8]}"


def outdated(name, old):
    """The newest release tag if it differs from `old`, else None."""
    tag = latest_tag(name)
    if tag.removeprefix("v") == old.get("version") and old.get("cargoHash"):
        return None
    return tag


def update_app(name, path, old, force):
    tag = outdated(name, old) or (force and latest_tag(name))
    if not tag:
        return None
    version = tag.removeprefix("v")
    hash_, date = prefetch(name, tag)
    new = {"version": version, "date": date, "hash": hash_, "cargoHash": ""}
    write(path, new)
    new["cargoHash"] = cargo_hash(name)
    write(path, new)
    return f"{old.get('version', '?')} -> {version}"


def main(argv):
    force = "--force" in argv
    check = "--check" in argv
    names = [a for a in argv if not a.startswith("--")]
    if not names:
        names = ["craft-fonts"] + sorted(p.stem for p in SOURCES.glob("*.json") if p.stem != "craft-fonts")

    if check:
        for name in names:
            if name != "craft-fonts" and outdated(name, json.loads((SOURCES / f"{name}.json").read_text())):
                print(name, flush=True)
        return 0

    failed = False
    for name in names:
        path = SOURCES / f"{name}.json"
        old = json.loads(path.read_text()) if path.exists() else {}
        log(f"==> {name}")
        try:
            if name == "craft-fonts":
                change = update_fonts(path, old, force)
            else:
                change = update_app(name, path, old, force)
        except Exception as e:  # keep going so one broken release doesn't block the rest
            failed = True
            log(f"error: {name}: {e}")
            if old:
                write(path, old)
            continue
        if change:
            print(f"{name}: {change}", flush=True)
        else:
            log("    up to date")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
