import importlib.util
from pathlib import Path
import tempfile
import unittest
import hashlib
import json
import os
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("vt_report", ROOT / "scripts/virustotal_scan.py")
import sys
vt = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = vt
spec.loader.exec_module(vt)

portable_spec = importlib.util.spec_from_file_location("windows_portable", ROOT / "scripts/package-windows-portable.py")
portable = importlib.util.module_from_spec(portable_spec)
portable_spec.loader.exec_module(portable)


class WindowsPortableTest(unittest.TestCase):
    def test_portable_contains_all_privacy_tools_and_preserves_runtime_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "runtime"
            files = {
                "Stashi Wallet.exe": b"wallet",
                "vcruntime140.dll": b"upstream signature bytes",
                "data/flutter_assets/example.json": b"{}",
                "i2p/i2pd.exe": b"optional router",
                "tor-pt/lyrebird.exe": b"optional bridge helper",
                "tor-pt/lyrebird.LICENSE.txt": b"upstream license",
                "app.PDB": b"debug symbols",
                "flutter_windows.lib": b"link library",
            }
            for name, data in files.items():
                file = source / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(data)
            archive = root / "portable.zip"
            portable.package_portable(source, archive, 1700000000)
            first = archive.read_bytes()
            with zipfile.ZipFile(archive) as zipped:
                self.assertEqual(set(zipped.namelist()), {
                    "Stashi Wallet.exe", "vcruntime140.dll", "data/flutter_assets/example.json",
                    "i2p/i2pd.exe", "tor-pt/lyrebird.exe", "tor-pt/lyrebird.LICENSE.txt",
                })
                self.assertEqual(zipped.read("vcruntime140.dll"), files["vcruntime140.dll"])
                for name in ("Stashi Wallet.exe", "i2p/i2pd.exe", "tor-pt/lyrebird.exe"):
                    self.assertEqual(zipped.read(name), files[name])
            portable.package_portable(source, archive, 1700000000)
            self.assertEqual(archive.read_bytes(), first)


@unittest.skipUnless(os.name == "nt" and shutil.which("pwsh"), "Windows PowerShell packaging checks")
class WindowsInstallerComponentTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "runtime"
        self.source.mkdir()
        (self.source / "Stashi Wallet.exe").write_bytes(b"MZfixture")
        self.output = self.root / "output"
        self.compiler = self.root / "compiler.ps1"
        self.compiler.write_text("$global:LASTEXITCODE = 0\n")
        for relative in ("tor-pt/lyrebird.exe", "i2p/i2pd.exe"):
            file = self.source / relative
            file.parent.mkdir(exist_ok=True)
            file.write_bytes(b"MZcompile-only fixture")
            Path(str(file) + ".provenance.json").write_text(json.dumps({
                "sha256": hashlib.sha256(file.read_bytes()).hexdigest(), "modified": False,
            }))
        (self.source / "tor-pt/lyrebird.LICENSE.txt").write_text("Fixture license notice")

    def package(self, *extra, succeeds=True):
        environment = os.environ.copy()
        environment.pop("WINDOWS_INCLUDE_I2PD", None)
        result = subprocess.run([
            "pwsh", "-NoProfile", "-File", str(ROOT / "scripts/package-windows-installer.ps1"),
            "-SourceDir", str(self.source), "-OutputDir", str(self.output),
            "-AppVersion", "1.2.2", "-IsccPath", str(self.compiler), *extra,
        ], env=environment, capture_output=True, text=True)
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_verified_lyrebird_and_i2pd_are_published_by_default(self):
        self.package()
        asset = self.output / "Stashi-Wallet-windows-component-lyrebird.exe"
        self.assertEqual(asset.read_bytes(), (self.source / "tor-pt/lyrebird.exe").read_bytes())
        self.assertEqual((self.output / "Stashi-Wallet-windows-component-i2pd.exe").read_bytes(),
                         (self.source / "i2p/i2pd.exe").read_bytes())
        entries = (self.output / "windows-components.iss").read_text(encoding="utf-8-sig")
        self.assertIn('Flags: external download ignoreversion', entries)
        self.assertIn(hashlib.sha256(asset.read_bytes()).hexdigest(), entries)
        self.assertIn('lyrebird.LICENSE.txt', entries)
        self.assertIn('i2pd.exe', entries)

    def test_signing_stage_can_use_unchanged_external_assets(self):
        self.package()
        shutil.rmtree(self.source / "tor-pt")
        shutil.rmtree(self.source / "i2p")
        self.package("-ComponentAssetDir", str(self.output))
        self.assertTrue((self.output / "Stashi-Wallet-windows-component-lyrebird.exe").exists())

    def test_modified_helper_is_rejected_before_packaging(self):
        (self.source / "tor-pt/lyrebird.exe").write_bytes(b"unexpected bytes")
        result = self.package(succeeds=False)
        self.assertIn('differs from verified upstream bytes', result.stderr)

    def test_modified_i2pd_is_rejected_before_packaging(self):
        (self.source / "i2p/i2pd.exe").write_bytes(b"unexpected bytes")
        self.package(succeeds=False)

    def test_warm_output_does_not_republish_retired_helpers(self):
        self.package("-IncludeI2pd")
        for name in ("snowflake-client", "obfs4proxy"):
            (self.output / f"Stashi-Wallet-windows-component-{name}.exe").write_bytes(b"old helper")
        self.package()
        self.assertEqual(
            {p.name for p in self.output.glob("Stashi-Wallet-windows-component-*.exe")},
            {"Stashi-Wallet-windows-component-lyrebird.exe", "Stashi-Wallet-windows-component-i2pd.exe"},
        )


@unittest.skipUnless(os.name == "nt" and shutil.which("pwsh"), "Windows signing policy checks")
class WindowsSigningPolicyTest(unittest.TestCase):
    def run_policy(self, corrupt=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / "runtime"
            runtime.mkdir()
            for name in ("Stashi Wallet.exe", "upstream.dll", "vcruntime140.dll", "lyrebird.exe"):
                (runtime / name).write_bytes(b"original bytes")
            (runtime / "tor-pt").mkdir()
            (runtime / "tor-pt/lyrebird.exe").write_bytes(b"nested upstream bytes")
            # Model an untrusted upstream signer and a newly signed application.
            # No certificates, trust stores or real signing services are used.
            runner = root / "policy.ps1"
            runner.write_text(r'''
param($Runtime, $Policy, $Log, $Corrupt)
$ErrorActionPreference = 'Stop'
$global:SignedWallet = $false
function Get-AuthenticodeSignature {
    param($LiteralPath)
    $name = Split-Path $LiteralPath -Leaf
    if ($name -eq 'upstream.dll') {
        $status = if ($Corrupt -eq 'yes') { 'HashMismatch' } else { 'NotTrusted' }
        return [pscustomobject]@{ Status = $status; SignerCertificate = 'upstream publisher' }
    }
    if ($name -eq 'Stashi Wallet.exe' -and $global:SignedWallet) {
        return [pscustomobject]@{ Status = 'NotTrusted'; SignerCertificate = 'test publisher' }
    }
    return [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null }
}
function Invoke-FakeSignTool {
    $args[-1] | Add-Content -LiteralPath $Log
    $global:SignedWallet = $true
    $global:LASTEXITCODE = 0
}
& $Policy -RuntimeDir $Runtime -CertificatePath 'unused.pfx' -SignToolPath 'Invoke-FakeSignTool'
''')
            log = root / "signed.txt"
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(runner), str(runtime),
                str(ROOT / "scripts/sign-windows-runtime.ps1"), str(log),
                "yes" if corrupt else "no",
            ], capture_output=True, text=True)
            for file in runtime.glob("*"):
                if file.is_file():
                    self.assertEqual(file.read_bytes(), b"original bytes")
            signed = [Path(line).name for line in log.read_text().splitlines()] if log.exists() else []
            return result, signed

    def test_existing_untrusted_signatures_and_unsigned_helpers_are_preserved(self):
        result, signed = self.run_policy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(signed, ["Stashi Wallet.exe"])

    def test_corrupt_upstream_signature_fails_signing(self):
        result, signed = self.run_policy(corrupt=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("corrupt upstream signature", result.stderr)
        self.assertNotIn("upstream.dll", signed)

class WindowsReleaseReportTest(unittest.TestCase):
    def test_optional_component_is_scanned_and_vendor_evidence_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Stashi-Wallet-windows-component-i2pd.exe").write_bytes(b"fixture")
            # The same selector used in CI must include independently downloadable helpers.
            files = vt.collect_files(root)
            self.assertEqual([p.name for p in files], ["Stashi-Wallet-windows-component-i2pd.exe"])
            vt.write_reports(root / "report", [{
                "name": files[0].name, "analysis_status": "completed",
                "vendor_detections": {"ESET": {"category": "malicious", "result": "Riskware.I2PD"}},
            }])
            self.assertIn("ESET: Riskware.I2PD", (root / "report/virustotal-results.md").read_text())

if __name__ == '__main__':
    unittest.main()
