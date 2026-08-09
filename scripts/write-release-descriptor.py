#!/usr/bin/env python3
"""Write one unsigned desktop_updater schema-3 descriptor."""

import argparse
import datetime as dt
import json
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--platform", choices=("windows", "macos", "android"), required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--build-number", type=int, required=True)
parser.add_argument("--url", required=True)
parser.add_argument("--sha256", required=True)
parser.add_argument("--length", type=int, required=True)
parser.add_argument("--kind", choices=("innoInstaller", "zip", "dmg"), required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--windows-thumbprint")
args = parser.parse_args()

if len(args.sha256) != 64 or any(c not in "0123456789abcdef" for c in args.sha256):
    raise SystemExit("sha256 must be 64 lowercase hexadecimal characters")

if args.platform == "windows":
    thumbprint = (args.windows_thumbprint or "").lower()
    if len(thumbprint) != 64:
        raise SystemExit("Windows descriptor requires the signed certificate SHA-256 thumbprint")
    install = {
        "strategy": "innoInstaller",
        "inno": {
            "silentArgs": ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"],
            "inheritInstallDirectory": True,
            "logFileName": "thing-update.log",
            "relaunchAfterInstall": True,
            "requiresElevation": "auto",
            "authenticode": {"required": True, "sha256Thumbprints": [thumbprint]},
        },
    }
elif args.platform == "macos":
    install = {
        "strategy": "wholeBundleReplace",
        "macosDmg": {"appBundleName": "Thing.app", "verifyPrimarySignature": True},
    }
else:
    install = {"strategy": "wholeDirectoryReplace"}

descriptor = {
    "schemaVersion": 3,
    "packageId": "local.munch.eventatlas",
    "appName": "Thing",
    "version": args.version,
    "buildNumber": args.build_number,
    "platform": args.platform,
    "channel": "stable",
    "artifact": {"kind": args.kind, "url": args.url, "sha256": args.sha256, "length": args.length},
    "install": install,
    "signature": {"algorithm": "ed25519", "publicKeyId": "thing-release-2026", "value": ""},
    "minimumUpdaterVersion": "2.7.0",
    "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
}
args.output.write_text(json.dumps(descriptor, indent=2) + "\n", encoding="utf-8")
