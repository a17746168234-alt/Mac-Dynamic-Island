#!/usr/bin/env python3
import importlib.util
from pathlib import Path

module_path = Path(__file__).parents[1] / "scripts" / "bump_version.py"
spec = importlib.util.spec_from_file_location("bump_version", module_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

assert module.next_version((1, 0, 8), "patch") == (1, 0, 9)
assert module.next_version((1, 0, 9), "patch") == (1, 1, 0)
assert module.next_version((1, 9, 9), "patch") == (2, 0, 0)
print("VersioningTests: PASS")
