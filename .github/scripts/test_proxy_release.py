import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("proxy_release", Path(__file__).with_name("proxy_release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ProxyReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.version_file = self.root / "version.env"
        self.version_file.write_text("MARKETING_VERSION=0.82.0\nBUILD_NUMBER=176\nFORK_VERSION=0.82.0-proxy.1\n")

    def test_fork_version_is_separate_from_native_version(self):
        info = release.metadata("v0.82.0-proxy.1", self.version_file)
        self.assertEqual(info["marketing_version"], "0.82.0")
        self.assertEqual(info["archive"], "CodexBar-0.82.0-proxy.1-macos-arm64.zip")

    def test_rejects_metadata_prerelease_and_shell_input(self):
        for tag in ["v0.82.0+proxy.1", "v0.82.0", "v0.82.0-proxy.0", "v0.82.0-proxy.1;echo", "../main"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.metadata(tag, self.version_file)

    def test_tag_must_match_both_versions(self):
        with self.assertRaises(ValueError):
            release.metadata("v0.82.1-proxy.1", self.version_file)
        with self.assertRaises(ValueError):
            release.metadata("v0.82.0-proxy.2", self.version_file)

    def test_native_bundle_disables_updates_and_preserves_numeric_version(self):
        info = release.metadata("v0.82.0-proxy.1", self.version_file)
        bundle = self.root / "CodexBar.app"
        (bundle / "Contents").mkdir(parents=True)
        values = {"CFBundleIdentifier": "com.steipete.codexbar", "CFBundleShortVersionString": "0.82.0",
                  "CFBundleVersion": "176", "CodexForkVersion": "0.82.0-proxy.1", "SUEnableAutomaticChecks": False}
        path = bundle / "Contents/Info.plist"
        path.write_bytes(plistlib.dumps(values))
        release.bundle_metadata(bundle, info)
        values["SUFeedURL"] = "https://example.com/appcast.xml"
        path.write_bytes(plistlib.dumps(values))
        with self.assertRaises(ValueError):
            release.bundle_metadata(bundle, info)

    def test_checksums_use_archive_bytes(self):
        path = self.root / "archive"
        path.write_bytes(b"abc")
        self.assertEqual(release.sha256(path), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")


if __name__ == "__main__":
    unittest.main()
