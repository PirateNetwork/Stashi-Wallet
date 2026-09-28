import pathlib
import subprocess
import sys
import tempfile
import unittest
import zipfile


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
MERGER = PROJECT_ROOT / "scripts" / "merge-installed-payloads.py"


class MergeInstalledPayloadsTests(unittest.TestCase):
    def merge(self, files: dict[str, str]) -> tuple[subprocess.CompletedProcess[str], str | None]:
        with tempfile.TemporaryDirectory() as temporary:
            archive = pathlib.Path(temporary) / "release-metadata.zip"
            output = pathlib.Path(temporary) / "build-payloads-v1.2.5.txt"
            with zipfile.ZipFile(archive, "w") as zipped:
                for name, content in files.items():
                    zipped.writestr(name, content)
            result = subprocess.run(
                [sys.executable, str(MERGER), str(archive), str(output)],
                capture_output=True,
                text=True,
                check=False,
            )
            return result, output.read_text() if output.exists() else None

    def test_x64_and_arm64_executables_can_have_distinct_digests(self) -> None:
        x64 = "a" * 64
        arm64 = "b" * 64
        result, manifest = self.merge(
            {
                "raw/linux-x64/installed-payload-linux.txt": f"{x64}  stashi-wallet\n",
                "raw/linux-arm64/installed-payload-linux-arm64.txt":
                    f"{arm64}  stashi-wallet\n",
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            manifest,
            f"{x64}  stashi-wallet\n{arm64}  stashi-wallet-linux-arm64\n",
        )

    def test_signed_payload_wins_over_unsigned_for_each_architecture(self) -> None:
        result, manifest = self.merge(
            {
                "raw/arm/installed-payload-linux-arm64-unsigned.txt":
                    f"{'a' * 64}  stashi-wallet\n",
                "raw/arm/installed-payload-linux-arm64.txt":
                    f"{'b' * 64}  stashi-wallet\n",
                "raw/x64/installed-payload-linux-unsigned.txt":
                    f"{'c' * 64}  stashi-wallet\n",
                "raw/x64/installed-payload-linux.txt":
                    f"{'d' * 64}  stashi-wallet\n",
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"{'b' * 64}  stashi-wallet-linux-arm64\n", manifest)
        self.assertIn(f"{'d' * 64}  stashi-wallet\n", manifest)
        self.assertNotIn("a" * 64, manifest)
        self.assertNotIn("c" * 64, manifest)

    def test_conflicting_digest_for_one_signed_name_is_rejected(self) -> None:
        result, manifest = self.merge(
            {
                "raw/linux/installed-payload-linux.txt":
                    f"{'a' * 64}  stashi-wallet\n",
                "raw/other/installed-payload-windows.txt":
                    f"{'b' * 64}  stashi-wallet\n",
            }
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Conflicting installed payload checksum", result.stderr)
        self.assertIsNone(manifest)

    def test_bad_payload_entry_is_rejected(self) -> None:
        result, manifest = self.merge(
            {"installed-payload-linux-arm64.txt": f"{'a' * 64}  ../stashi-wallet\n"}
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid installed payload checksum", result.stderr)
        self.assertIsNone(manifest)


if __name__ == "__main__":
    unittest.main()
