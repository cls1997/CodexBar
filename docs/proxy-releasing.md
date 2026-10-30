---
summary: Publish the locally signed proxy fork and synchronize its Homebrew tap.
read_when:
  - Releasing CodexBar Proxy
  - Maintaining cls1997/homebrew-tap
---

# Proxy fork releases

This fork uses `.github/workflows/proxy-release.yml`, not the upstream signed
Sparkle/appcast publication chain. The upstream release validator is restricted
to `steipete/CodexBar`. No upstream certificate, provisioning profile, Sparkle
private key, appcast update or upstream Homebrew token is used.

## Versions

`version.env` separates three values:

- `MARKETING_VERSION=0.82.0`: native three-component bundle version.
- `BUILD_NUMBER=176`: positive, increasing native build number.
- `FORK_VERSION=0.82.0-proxy.1`: GitHub/Cask release version, without the tag's `v`.

For another fork revision, increment both BUILD_NUMBER and the proxy revision.
For an upstream update, change MARKETING_VERSION and start its proxy revision at 1.
The packager also records FORK_VERSION as `CodexForkVersion` in Info.plist.
The release policy checks that the tag, native version, build and archive agree.

## Publish

1. Commit the version change and all source changes on the fork's main branch.
2. Create an annotated tag such as `v0.82.0-proxy.1` at that commit and push it.
3. The Proxy Release workflow uses the public macos-26 arm64 runner with Xcode 26.5,
   runs release policy tests, make check and focused transport/settings tests,
   then packages using `ARCHES=arm64 CODEXBAR_SIGNING=adhoc`.
4. Bundle identity, version, disabled update feed, ad-hoc signature and arm64
   architecture are verified before creating the archive and SHA256SUMS.
5. A separate contents-write job downloads the verified artifact and creates the
   fork's GitHub Release. Only the workflow's repository-scoped GITHUB_TOKEN is needed.

Publication is CI-only. A manual workflow dispatch requires an existing tag and
uses dry-run mode by default; disable dry-run to publish. Tags must point to a
commit contained in origin/main. The workflow never overwrites an existing release.
If an upload fails after creating a draft, inspect and remove that unpublished
draft before retrying; do not replace assets of a published version.

The release is explicitly marked as a normal GitHub release even though its
fork suffix uses a SemVer pre-release-shaped tag. Its assets are:

- `CodexBar-0.82.0-proxy.1-macos-arm64.zip` (contains `CodexBar.app`)
- `SHA256SUMS`
- `release.json` (source commit, versions, platform, signing and archive digest)

## Homebrew handoff

The separate [tap](https://github.com/cls1997/homebrew-tap) polls public releases
every 30 minutes and supports a manual Update casks dispatch. Its own GITHUB_TOKEN
can write that repository; no cross-repository credential is needed. It validates
the release manifest and hashes the downloaded archive before committing
`Casks/codexbar-proxy.rb`. Drafts, prereleases and version downgrades are ignored.
GitHub schedules can be delayed or disabled after prolonged repository inactivity.

For an immediate handoff, run the tap's Update casks workflow after publication.
Verify the Cask URL and SHA256 against the release before announcing it.

```sh
brew install --cask cls1997/tap/codexbar-proxy
brew update
brew upgrade --cask cls1997/tap/codexbar-proxy
```

The Cask installs `CodexBar Proxy.app`, conflicts with the official `codexbar`
Cask, and does not declare auto_updates. No uninstall zap or credential deletion
is configured. Both app variants share a bundle ID, so avoid running them together.

This is an ad-hoc-signed, non-notarized distribution. Homebrew does not grant it
Apple notarization or iCloud authorization. Gatekeeper remains enabled. iCloud
and all built-in update mechanisms remain disabled in the app.
