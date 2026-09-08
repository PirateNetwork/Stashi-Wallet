"""Exercise the generation wrapper without compiling Rust or downloading tools."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class FrbGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.cargo = self.root / "cargo"
        (self.cargo / "bin").mkdir(parents=True)
        (self.root / "crates").mkdir()
        generated = self.root / "app/lib/core/ffi/generated"
        generated.mkdir(parents=True)
        # Old checked-in files must never turn a failed generation into success.
        (generated / "api.dart").write_text("old output")
        (generated / "frb_generated.dart").write_text("old output")
        (self.root / "flutter_rust_bridge.yaml").write_text("rust_input: crate::api\n")
        shutil.copyfile(ROOT / "generate_ffi_bindings.sh", self.root / "generate.sh")
        for name in ("flutter", "dart"):
            self.executable(self.bin / name, "exit 0\n")
        self.executable(
            self.bin / "cargo",
            'if [ "$1" = install ]; then printf "%s\\n" "$*" > "$TEST_INSTALL_LOG"; fi\nexit 0\n',
        )
        self.executable(
            self.cargo / "bin/flutter_rust_bridge_codegen",
            'if [ "$1" = --version ]; then echo "flutter_rust_bridge_codegen ${TEST_FRB_VERSION}"; exit 0; fi\n'
            'exit "${TEST_GENERATION_EXIT}"\n',
        )
        self.bash = shutil.which("bash")
        if os.name == "nt":
            candidate = Path("C:/Program Files/Git/bin/bash.exe")
            if candidate.exists():
                self.bash = str(candidate)
        if not self.bash:
            self.skipTest("Bash is required")

    @staticmethod
    def executable(path, body):
        path.write_text("#!/bin/bash\n" + body, encoding="utf-8", newline="\n")
        path.chmod(0o755)

    def run_generator(self, version="2.13.0", exit_code="0"):
        def shell_path(path):
            value = path.as_posix()
            if os.name == "nt":
                return "/" + value[0].lower() + value[2:]
            return value

        env = dict(os.environ)
        env.update(
            FLUTTER_PATH=shell_path(self.bin),
            CARGO_HOME=shell_path(self.cargo),
            FRB_CODEGEN_VERSION="2.13.0",
            TEST_FRB_VERSION=version,
            TEST_GENERATION_EXIT=exit_code,
            TEST_INSTALL_LOG=shell_path(self.root / "install.log"),
        )
        return subprocess.run(
            [self.bash, str(self.root / "generate.sh")],
            cwd=self.root, env=env, capture_output=True, timeout=30,
        )

    def test_failure_is_not_hidden_by_existing_outputs(self):
        result = self.run_generator(exit_code="42")
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)

    def test_matching_generator_is_reused(self):
        result = self.run_generator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / "install.log").exists())

    def test_mismatched_generator_installs_exact_version(self):
        result = self.run_generator(version="2.11.1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            (self.root / "install.log").read_text().strip(),
            "install flutter_rust_bridge_codegen --locked --version 2.13.0 --force",
        )


if __name__ == "__main__":
    unittest.main()
