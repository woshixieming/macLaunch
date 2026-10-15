#!/usr/bin/env python3
"""Compile and run reorder regressions against the real AppCatalog on macOS."""

import pathlib
import subprocess
import sys
import tempfile


def main():
    if sys.platform != "darwin":
        print("ERROR: These tests require macOS and the Xcode Swift toolchain.", file=sys.stderr)
        return 1

    root = pathlib.Path(__file__).resolve().parents[1]
    sources = [
        root / "MacLaunch/AppCatalog.swift",
        root / "MacLaunch/AppSettings.swift",
        root / "MacLaunch/AppInfo.swift",
        root / "tests/AppCatalogReorderTests.swift",
    ]
    with tempfile.TemporaryDirectory(prefix="maclaunch-reorder-tests-") as directory:
        executable = pathlib.Path(directory) / "reorder-tests"
        subprocess.run(
            ["xcrun", "swiftc", "-swift-version", "6", *map(str, sources), "-o", str(executable)],
            cwd=root,
            check=True,
            timeout=120,
        )
        subprocess.run([str(executable)], cwd=root, check=True, timeout=30)
    return 0


if __name__ == "__main__":
    sys.exit(main())
