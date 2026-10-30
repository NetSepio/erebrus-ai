#!/usr/bin/env python3
"""Write the release manifest, checksums, and notes for a GitHub Release.

Usage:
  scripts/write-release-manifest.py --dist dist --tag v1.1.1 --version 1.1.1 \
    --build 3 --commit <sha> --repo NetSepio/erebrus-ai \
    [--playstore-cert <sha256>] [--dappstore-cert <sha256>] \
    [--changelog changelog-section.md] [--notes notes.md]

Writes into --dist:
  erebrus-ai-manifest-<tag>.json   every asset with platform, size, SHA-256, URL
  erebrus-ai-sha256sums-<tag>.txt  `sha256sum -c` compatible checksums
"""

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

APP_NAME = "Erebrus AI"
PACKAGE_NAME = "com.erebrus.ai"

# (filename prefix, platform, store, label for the notes table)
KINDS = [
    ("erebrus-ai-playstore-", "android", "playstore", "Android sideload (Play Store key)"),
    ("erebrus-ai-dappstore-", "android", "dappstore", "Solana Mobile / dApp Store (dApp Store key)"),
    ("erebrus-ai-macos-", "macos", None, "macOS `.app`"),
    ("erebrus-ai-windows-", "windows", None, "Windows"),
    ("erebrus-ai-linux-", "linux", None, "Linux bundle (x64)"),
    ("erebrus-ai-r8-mapping-", "android", None, "R8 mapping files for deobfuscating Android stack traces"),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dist", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--playstore-cert", default="")
    parser.add_argument("--dappstore-cert", default="")
    parser.add_argument("--changelog", type=Path)
    parser.add_argument("--notes", type=Path)
    args = parser.parse_args()

    manifest_name = f"erebrus-ai-manifest-{args.tag}.json"
    sums_name = f"erebrus-ai-sha256sums-{args.tag}.txt"
    certs = {"playstore": args.playstore_cert, "dappstore": args.dappstore_cert}
    download = f"https://github.com/{args.repo}/releases/download/{args.tag}"

    assets = []
    rows = []
    for path in sorted(args.dist.iterdir()):
        if not path.is_file() or path.name in (manifest_name, sums_name):
            continue
        kind = next((k for k in KINDS if path.name.startswith(k[0])), None)
        if kind is None:
            raise SystemExit(f"::error::Unexpected release asset {path.name}")
        _, platform, store, label = kind
        if path.suffix == ".aab":
            label = "Android App Bundle for the Play Console (Play Store key)"
        asset = {
            "name": path.name,
            "platform": platform,
            "size": path.stat().st_size,
            "sha256": sha256(path),
            "url": f"{download}/{path.name}",
        }
        if store:
            asset["store"] = store
            asset["format"] = path.suffix.lstrip(".")
            asset["packageName"] = PACKAGE_NAME
            if certs[store]:
                asset["signingCertSha256"] = certs[store]
        assets.append(asset)
        rows.append(f"| `{path.name}` | {label} |")

    if not assets:
        raise SystemExit("::error::No release assets found")

    manifest = {
        "schemaVersion": 1,
        "app": APP_NAME,
        "version": args.version,
        "build": args.build,
        "tag": args.tag,
        "commit": args.commit,
        "publishedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "releaseUrl": f"https://github.com/{args.repo}/releases/tag/{args.tag}",
        "assets": assets,
    }
    (args.dist / manifest_name).write_text(json.dumps(manifest, indent=2) + "\n")
    # Checksums cover the manifest too, so it can be verified like any asset.
    checked = assets + [{"name": manifest_name, "sha256": sha256(args.dist / manifest_name)}]
    (args.dist / sums_name).write_text(
        "".join(f"{a['sha256']}  {a['name']}\n" for a in checked)
    )

    if args.notes:
        rows.append(f"| `{manifest_name}` | Release manifest (sizes, SHA-256, signing certificates) |")
        rows.append(f"| `{sums_name}` | Checksums (`sha256sum -c {sums_name}`) |")
        lines = [
            f"Version: `{args.version}+{args.build}`",
            "",
            "| Artifact | Platform |",
            "|----------|----------|",
            *rows,
        ]
        if any(a.get("store") for a in assets):
            lines += ["", f"Both APKs use `{PACKAGE_NAME}` with different certificates — install one."]
        if args.changelog and args.changelog.is_file():
            lines += ["", "## Changes", "", args.changelog.read_text().strip()]
        args.notes.write_text("\n".join(lines) + "\n")

    print(f"Wrote {manifest_name} and {sums_name} for {len(assets)} assets")


if __name__ == "__main__":
    main()
