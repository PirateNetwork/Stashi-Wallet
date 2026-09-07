"""Exercise the real PowerShell fetch path with local, checksum-pinned archives."""

import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.name == "nt" and shutil.which("powershell.exe"),
                     "Requires Windows PowerShell and native Windows tar")
class WindowsAssetFetchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wallet fetch with spaces ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        self.script = scripts / "fetch-tor-i2p-assets.ps1"
        shutil.copyfile(ROOT / "scripts/fetch-tor-i2p-assets.ps1", self.script)
        self.archive = self.root / "fixture.tar.gz"
        self.helper = b"fixture executable bytes, never executed"
        self.license = b"fixture upstream license"
        self.environment = os.environ.copy()
        self.environment.pop("SKIP_TOR_I2P_FETCH", None)
        # Let Windows PowerShell discover its own modules when the test runner
        # was launched from PowerShell 7 with a different PSModulePath.
        for key in list(self.environment):
            if key.upper() == "PSMODULEPATH":
                del self.environment[key]
        self.environment["PSModulePath"] = str(
            Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/Modules")
        # An executable named tar.exe takes precedence over the system tool.
        # where.exe rejects tar's arguments if the fetch accidentally uses PATH.
        shadow = self.root / "shadow tools"
        shadow.mkdir()
        shutil.copyfile(Path(os.environ["SystemRoot"]) / "System32/where.exe", shadow / "tar.exe")
        self.environment["PATH"] = str(shadow) + os.pathsep + self.environment["PATH"]

    def make_archive(self, include_license=True):
        with tarfile.open(self.archive, "w:gz") as archive:
            entries = {"tor/pluggable_transports/lyrebird.exe": self.helper}
            if include_license:
                entries["docs/lyrebird.txt"] = self.license
            for name, data in entries.items():
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        return hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def fetch(self, checksum):
        return subprocess.run([
            "powershell.exe", "-NoProfile", "-File", str(self.script),
            "-Components", "bridges", "-TorBundleUrl", self.archive.as_uri(),
            "-TorBundleSha256", checksum,
        ], env=self.environment, capture_output=True, text=True, timeout=60)

    def test_native_extraction_ignores_path_shadow_and_preserves_bytes(self):
        checksum = self.make_archive()
        result = self.fetch(checksum)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        destination = self.root / "app/tor-pt/windows"
        self.assertEqual((destination / "lyrebird.exe").read_bytes(), self.helper)
        self.assertEqual((destination / "lyrebird.LICENSE.txt").read_bytes(), self.license)
        provenance = json.loads((destination / "lyrebird.exe.provenance.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(provenance["archiveHash"], checksum)
        self.assertEqual(provenance["sha256"], hashlib.sha256(self.helper).hexdigest())
        self.assertFalse(provenance["modified"])
        self.assertEqual(list((self.root / "output/release-investigation/privacy-assets").iterdir()), [])

    def test_checksum_mismatch_stops_before_staging(self):
        self.make_archive()
        result = self.fetch("0" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA256 mismatch", result.stderr)
        self.assertFalse((self.root / "app").exists())

    def test_git_bash_tar_precedes_windows_tools(self):
        git_tar = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/usr/bin/tar.exe"
        if not git_tar.is_file():
            self.skipTest("Git for Windows GNU tar is not installed")
        self.environment["PATH"] = str(git_tar.parent) + os.pathsep + self.environment["PATH"]
        checksum = self.make_archive()
        # Reproduce GNU tar's interpretation of the native drive-letter path.
        old = subprocess.run([str(git_tar), "-tf", str(self.archive)],
                             capture_output=True, text=True, timeout=15)
        self.assertNotEqual(old.returncode, 0)
        self.assertIn("Cannot connect to", old.stderr)
        result = self.fetch(checksum)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "app/tor-pt/windows/lyrebird.exe").read_bytes(), self.helper)

    def test_missing_license_fails_extraction(self):
        result = self.fetch(self.make_archive(include_license=False))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cannot extract Lyrebird", result.stderr)
        self.assertFalse((self.root / "app").exists())


if __name__ == "__main__":
    unittest.main()
