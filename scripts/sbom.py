#!/usr/bin/env python3
"""Writes a CycloneDX SBOM for a built EventHorizon binary.

Usage: python3 scripts/sbom.py <binary> <output.json>

Components are the Swift package dependencies (from Package.swift) plus every
library the binary links against (from otool -L). All linked libraries ship with
macOS, so they are listed as Apple operating system components.
"""
import datetime
import json
import plistlib
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def app_version():
    with open(ROOT / "Info.plist", "rb") as plist:
        return plistlib.load(plist)["CFBundleShortVersionString"]


def package_dependencies():
    output = subprocess.run(["swift", "package", "show-dependencies", "--format", "json"],
                            cwd=ROOT, check=True, capture_output=True, text=True).stdout
    found = []

    def walk(node):
        for dependency in node.get("dependencies", []):
            found.append({
                "type": "library",
                "name": dependency["name"],
                "version": dependency["version"],
                "purl": f"pkg:swift/{dependency['url'].removeprefix('https://').removesuffix('.git')}@{dependency['version']}",
                "externalReferences": [{"type": "vcs", "url": dependency["url"]}],
            })
            walk(dependency)

    walk(json.loads(output))
    return found


def linked_libraries(binary):
    output = subprocess.run(["otool", "-L", binary], check=True, capture_output=True, text=True).stdout
    paths = sorted({line.split()[0] for line in output.splitlines()[1:] if line.strip()})
    return [{
        "type": "framework" if ".framework/" in path else "library",
        "name": Path(path.split(".framework/")[0]).name if ".framework/" in path else Path(path).name,
        "supplier": {"name": "Apple Inc."},
        "description": f"Provided by macOS, loaded from {path}",
        "scope": "required",
    } for path in paths]


def main():
    binary, output = sys.argv[1], sys.argv[2]
    version = app_version()
    sbom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "version": 1,
        "metadata": {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "tools": {"components": [{"type": "application", "name": "scripts/sbom.py"}]},
            "component": {
                "type": "application",
                "name": "EventHorizon",
                "version": version,
                "purl": f"pkg:github/zapeman02/eventhorizon@v{version}",
                "licenses": [{"license": {"id": "MIT"}}],
                "externalReferences": [{"type": "vcs", "url": "https://github.com/Zapeman02/EventHorizon"}],
            },
        },
        "components": package_dependencies() + linked_libraries(binary),
    }
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    Path(output).write_text(json.dumps(sbom, indent=2) + "\n")
    print(f"SBOM with {len(sbom['components'])} components written to {output}")


if __name__ == "__main__":
    main()
