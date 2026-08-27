#!/usr/bin/env python3
"""Update Mac灵动岛's semantic version and Xcode build number."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


PROJECT_FILE = Path(__file__).resolve().parents[1] / "MacDynamicIsland.xcodeproj" / "project.pbxproj"
VERSION_PATTERN = re.compile(r"(MARKETING_VERSION = )(\d+)\.(\d+)\.(\d+)(;)")
BUILD_PATTERN = re.compile(r"(CURRENT_PROJECT_VERSION = )(\d+)(;)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bump the app version: patch for normal releases, minor for larger updates."
    )
    parser.add_argument("kind", choices=("patch", "minor", "major", "set"))
    parser.add_argument("version", nargs="?", help="Required only with 'set', for example 1.2.0")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def next_version(old_version: tuple[int, int, int], kind: str) -> tuple[int, int, int]:
    major, minor, patch = old_version
    if kind == "patch":
        if patch < 9:
            return major, minor, patch + 1
        if minor < 9:
            return major, minor + 1, 0
        return major + 1, 0, 0
    if kind == "minor":
        return (major, minor + 1, 0) if minor < 9 else (major + 1, 0, 0)
    if kind == "major":
        return major + 1, 0, 0
    raise ValueError(f"Unsupported version kind: {kind}")


def main() -> None:
    args = parse_args()
    text = PROJECT_FILE.read_text(encoding="utf-8")
    versions = {(int(a), int(b), int(c)) for _, a, b, c, _ in VERSION_PATTERN.findall(text)}
    builds = {int(value) for _, value, _ in BUILD_PATTERN.findall(text)}
    if len(versions) != 1 or len(builds) != 1:
        raise SystemExit(f"Expected one shared version and build number, found versions={versions}, builds={builds}")

    old_version = versions.pop()
    old_build = builds.pop()
    if args.kind == "set":
        if not args.version or not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
            raise SystemExit("set requires an X.Y.Z version")
        new_version = tuple(map(int, args.version.split(".")))
    else:
        new_version = next_version(old_version, args.kind)

    new_version_text = ".".join(map(str, new_version))
    updated = VERSION_PATTERN.sub(lambda match: f"{match.group(1)}{new_version_text}{match.group(5)}", text)
    updated = BUILD_PATTERN.sub(lambda match: f"{match.group(1)}{old_build + 1}{match.group(3)}", updated)

    print(f"version {'.'.join(map(str, old_version))} -> {new_version_text}")
    print(f"build {old_build} -> {old_build + 1}")
    if not args.dry_run:
        PROJECT_FILE.write_text(updated, encoding="utf-8")


if __name__ == "__main__":
    main()
