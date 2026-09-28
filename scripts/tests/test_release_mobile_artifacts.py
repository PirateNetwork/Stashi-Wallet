"""Exercise mobile release selection with both signed and fallback iOS inputs."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).parents[2]
COLLECTOR = ROOT / "scripts" / "collect-github-release-assets.sh"


@unittest.skipIf(os.name == "nt", "Run this Bash packaging test on Linux")
class ReleaseMobileArtifactsTest(unittest.TestCase):
    def _collect(
        self, signed_ios: bool, signed_android: bool = True
    ) -> tuple[set[str], set[str]]:
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            artifacts = base / "artifacts"
            artifacts.mkdir()
            files = {
                "Stashi-Wallet-android-V8.apk",
                "Stashi-Wallet-android-V7.apk",
                "Stashi-Wallet-android-V8-unsigned.apk",
                "Stashi-Wallet-android-V7-unsigned.apk",
                "Stashi-Wallet-android-unsigned.aab",
                "Stashi-Wallet-ios-unsigned.ipa",
                "piratewallet-cli",
                "librust-linux-x86_64.so",
                "libpirate_ffi_native.so",
                "PirateWalletNative.xcframework.zip",
                "pirate-android-sdk-package.zip",
                "react-native-pirate-wallet-package.zip",
            }
            if signed_ios:
                files.add("Stashi-Wallet-ios.ipa")
            if signed_android:
                files.add("Stashi-Wallet-android.aab")
            for name in files:
                (artifacts / name).write_bytes(name.encode())

            release = base / "release"
            collector = base / "collect-release.sh"
            collector.write_text(COLLECTOR.read_text(encoding="utf-8"), encoding="utf-8")
            # Use a deterministic ZIP implementation; some test hosts provide a
            # restricted /usr/bin/zip wrapper rather than Info-ZIP.
            tool_dir = base / "bin"
            tool_dir.mkdir()
            zip_tool = tool_dir / "zip"
            zip_tool.write_text(
                "#!/usr/bin/env python3\n"
                "import pathlib, sys, zipfile\n"
                "assert sys.argv[1] == '-qr'\n"
                "with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as z:\n"
                "    for p in sorted(pathlib.Path('.').rglob('*')):\n"
                "        if p.is_file(): z.write(p, p.as_posix())\n",
                encoding="utf-8",
            )
            zip_tool.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = f"{tool_dir}{os.pathsep}{env['PATH']}"
            env["RELEASE_SIGNING_DIR"] = str(ROOT / "release-signing")
            env.pop("GITHUB_REPOSITORY", None)
            env["GITHUB_REF_NAME"] = "v0.0.0"
            env.update({
                key: "true" for key in (
                    "CLI_CHANGED", "QORTAL_JNI_CHANGED", "NATIVE_FFI_CHANGED",
                    "IOS_SDK_CHANGED", "ANDROID_SDK_CHANGED",
                    "REACT_NATIVE_PLUGIN_CHANGED",
                )
            })
            result = subprocess.run(
                [
                    "bash",
                    str(collector),
                    str(artifacts),
                    str(release),
                    str(base / "metadata"),
                    str(base / "developer"),
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            bundle = release / "Stashi-Wallet-mobile-store-test-builds.zip"
            with zipfile.ZipFile(bundle) as archive:
                bundled = set(archive.namelist())
            published = {path.name for path in release.iterdir()}
            return published, bundled

    def test_signed_mobile_bundle_and_only_v8_direct_download(self) -> None:
        published, bundled = self._collect(signed_ios=True)
        self.assertIn("Stashi-Wallet-android-V8.apk", published)
        self.assertNotIn("Stashi-Wallet-android-V7.apk", published)
        self.assertEqual(
            bundled,
            {"Stashi-Wallet-android.aab", "Stashi-Wallet-ios.ipa"},
        )

    def test_unsigned_ios_fallback_is_clearly_labeled(self) -> None:
        _, bundled = self._collect(signed_ios=False)
        self.assertEqual(
            bundled,
            {"Stashi-Wallet-android.aab", "Stashi-Wallet-ios-unsigned.ipa"},
        )

    def test_unsigned_android_bundle_is_not_published(self) -> None:
        _, bundled = self._collect(signed_ios=False, signed_android=False)
        self.assertEqual(bundled, {"Stashi-Wallet-ios-unsigned.ipa"})


if __name__ == "__main__":
    unittest.main()
