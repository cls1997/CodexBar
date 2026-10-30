"""Release the locally signed macOS proxy fork; never touch upstream or its appcast."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "cls1997/CodexBar"
TAG_PATTERN = re.compile(r"v(\d+\.\d+\.\d+)-proxy\.([1-9]\d*)")


def metadata(tag, version_file=None):
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise ValueError("Expected vX.Y.Z-proxy.N with N >= 1")
    values = dict(line.split("=", 1) for line in (version_file or ROOT / "version.env").read_text().splitlines()
                  if "=" in line and not line.startswith("#"))
    version = tag[1:]
    if values.get("FORK_VERSION") != version or values.get("MARKETING_VERSION") != match[1]:
        raise ValueError("Tag must match FORK_VERSION and the numeric MARKETING_VERSION")
    if not re.fullmatch(r"[1-9]\d*", values.get("BUILD_NUMBER", "")):
        raise ValueError("BUILD_NUMBER must be positive")
    return {"version": version, "marketing_version": match[1], "build": values["BUILD_NUMBER"],
            "tag": tag, "archive": f"CodexBar-{version}-macos-arm64.zip"}


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def validate(tag):
    info = metadata(tag)
    commit = git("rev-parse", "HEAD")
    if git("rev-parse", f"refs/tags/{tag}^{{commit}}") != commit:
        raise ValueError("Checkout must be the exact tagged commit")
    subprocess.run(["git", "merge-base", "--is-ancestor", commit, "origin/main"], cwd=ROOT, check=True)
    info["commit"] = commit
    return info


def bundle_metadata(bundle, info):
    with (bundle / "Contents/Info.plist").open("rb") as stream:
        plist = plistlib.load(stream)
    expected = {"CFBundleIdentifier": "com.steipete.codexbar",
                "CFBundleShortVersionString": info["marketing_version"], "CFBundleVersion": info["build"],
                "CodexForkVersion": info["version"]}
    for key, value in expected.items():
        if str(plist.get(key)) != value:
            raise ValueError(f"Unexpected bundle field: {key}")
    if plist.get("SUFeedURL") or plist.get("SUEnableAutomaticChecks"):
        raise ValueError("The proxy edition must not enable Sparkle updates")
    if (bundle / "Contents/embedded.provisionprofile").exists():
        raise ValueError("Ad-hoc release must not embed upstream provisioning")


def prepare(tag, bundle, directory):
    info = validate(tag)
    bundle_metadata(bundle, info)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    signature = subprocess.check_output(["codesign", "-dv", "--verbose=4", str(bundle)], stderr=subprocess.STDOUT,
                                        text=True)
    if "Signature=adhoc" not in signature:
        raise ValueError("Expected local ad-hoc signing")
    binary = bundle / "Contents/MacOS/CodexBar"
    if subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip() != "arm64":
        raise ValueError("Expected an arm64 app")
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / info["archive"]
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(bundle), str(archive)], check=True)
    info.update(repository=REPOSITORY, architecture="arm64", signing="adhoc", sha256=sha256(archive))
    (directory / "release.json").write_text(json.dumps(info, indent=2) + "\n")
    (directory / "SHA256SUMS").write_text(f'{info["sha256"]}  {info["archive"]}\n')
    (directory / "NOTES.md").write_text(f'''CodexBar Proxy {info["version"]}

- Application-wide HTTP/SOCKS5 proxy settings, optional authentication and bypass list.
- iCloud sync and all built-in update checks are disabled. Updates are managed with Homebrew.
- Apple Silicon; macOS 14 or later.
- Locally signed (ad-hoc), not Apple-notarized. macOS may require approval on first launch.

Install after the tap has synchronized this release:

```sh
brew install --cask cls1997/tap/codexbar-proxy
```

Upgrade:

```sh
brew update
brew upgrade --cask cls1997/tap/codexbar-proxy
```

Source commit: `{info["commit"]}`. Native app version: {info["marketing_version"]} ({info["build"]}).
''')
    return info


def publish(tag, directory):
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise ValueError("Publication is only allowed from this fork's GitHub Actions")
    info = validate(tag)
    manifest = json.loads((directory / "release.json").read_text())
    if any(manifest.get(key) != info[key] for key in info):
        raise ValueError("Artifact does not belong to the checked-out release")
    if manifest.get("repository") != REPOSITORY or sha256(directory / info["archive"]) != manifest["sha256"]:
        raise ValueError("Release artifact checksum or repository mismatch")
    common = ["--repo", REPOSITORY]
    existing = subprocess.run(["gh", "release", "view", tag, *common], capture_output=True)
    if existing.returncode == 0:
        raise ValueError("Release already exists; never overwrite published assets or a draft implicitly")
    subprocess.run(["gh", "release", "create", tag, *common, "--verify-tag", "--target", info["commit"],
                    "--draft", "--prerelease=false", "--title", f'CodexBar Proxy {info["version"]}',
                    "--notes-file", str(directory / "NOTES.md"), str(directory / info["archive"]),
                    str(directory / "SHA256SUMS"), str(directory / "release.json")], check=True)
    subprocess.run(["gh", "release", "edit", tag, *common, "--draft=false", "--prerelease=false", "--latest"],
                   check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["validate", "prepare", "publish"])
    parser.add_argument("--tag", required=True)
    parser.add_argument("--bundle", type=Path, default=ROOT / "CodexBar.app")
    parser.add_argument("--directory", type=Path, default=ROOT / ".release-dist")
    args = parser.parse_args()
    if args.command == "publish":
        publish(args.tag, args.directory)
        return
    info = prepare(args.tag, args.bundle, args.directory) if args.command == "prepare" else validate(args.tag)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            for key in ("version", "archive", "commit"):
                stream.write(f"{key}={info[key]}\n")
    print(json.dumps(info, indent=2))


if __name__ == "__main__":
    main()
