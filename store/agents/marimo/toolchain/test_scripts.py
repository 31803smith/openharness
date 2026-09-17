"""setup.sh, doctor.sh, init-workspace.sh and viewer.sh, run for real against a scratch install whose
PATH holds only stub commands (and the few coreutils the scripts use), so every ok / miss line is
reached without a network, a venv or a marimo on the machine:

    python3 -m unittest toolchain/test_scripts.py
"""
import shutil, subprocess, tempfile, unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent
BASH = "/bin/bash"
COREUTILS = ("dirname", "cat", "mkdir", "tail")
VERSION = (PACKAGE / "MARIMO_VERSION").read_text().strip()


class Sandbox:
    """An install dir with the package's scripts, a bin/ of stubs as the whole PATH, and a log of
    every stub call."""

    def __init__(self, test: unittest.TestCase):
        tmp = tempfile.TemporaryDirectory()
        test.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.install = self.root / "install"
        (self.install / "toolchain").mkdir(parents=True)
        for script in PACKAGE.glob("toolchain/*.sh"):
            shutil.copy(script, self.install / "toolchain" / script.name)
        for name in ("MARIMO_VERSION", "viewer.sh"):
            shutil.copy(PACKAGE / name, self.install / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls.log"
        self.calls.touch()
        for name in COREUTILS:
            real = next(p for p in (Path("/bin") / name, Path("/usr/bin") / name) if p.exists())
            (self.bin / name).symlink_to(real)

    def stub(self, name: str, body: str = "", where: Path | None = None) -> Path:
        path = (where or self.bin) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f'#!/bin/bash\necho "{name} $*" >> "$CALLS"\n{body}\n')
        path.chmod(0o755)
        return path

    def venv(self, root: Path | None = None) -> None:
        """A .venv whose python logs pip and whose marimo prints a version the way marimo does."""
        bin_ = (root or self.install) / ".venv" / "bin"
        self.stub("python", "exit ${PIP_EXIT:-0}", where=bin_)
        self.stub("marimo", f'echo "{VERSION}"', where=bin_)

    def run(self, script: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run([BASH, str(self.install / script)], cwd=cwd or self.install,
                              env={"PATH": str(self.bin), "CALLS": str(self.calls), **env},
                              capture_output=True, text=True, timeout=60)

    def logged(self) -> list[str]:
        return self.calls.read_text().splitlines()


class Doctor(unittest.TestCase):
    def test_ready(self):
        box = Sandbox(self)
        box.venv()
        r = box.run("toolchain/doctor.sh")
        self.assertEqual((r.returncode, r.stdout), (0, f"ok   marimo {VERSION}\n"), r.stderr)

    def test_no_venv_is_a_miss(self):
        r = Sandbox(self).run("toolchain/doctor.sh")
        self.assertEqual((r.returncode, r.stdout), (1, "miss .venv/bin/marimo — run toolchain/setup.sh\n"))


def python(version: str, fits: bool) -> str:
    """A pythonX.Y stub: the version probe passes or not; `-m venv .venv` makes a stub venv."""
    return (f'case "$1" in\n'
            f'  -c) exit {0 if fits else 1} ;;\n'
            f'  --version) echo "Python {version}" ;;\n'
            f'  -m) mkdir -p .venv/bin; cp "$STUB_VENV/python" "$STUB_VENV/marimo" .venv/bin/ ;;\n'
            f'esac')


class Setup(unittest.TestCase):
    def sandbox(self) -> Sandbox:
        box = Sandbox(self)
        box.venv(box.root / "template")          # what `python -m venv` copies in
        (box.bin / "cp").symlink_to("/bin/cp")
        return box

    def run_setup(self, box: Sandbox, **env: str) -> subprocess.CompletedProcess:
        return box.run("toolchain/setup.sh", STUB_VENV=str(box.root / "template" / ".venv" / "bin"), **env)

    def test_the_first_python_that_fits_makes_the_venv(self):
        box = self.sandbox()
        box.stub("python3.12", python("3.12.9", fits=False))   # present but refused
        box.stub("python3.11", python("3.11.4", fits=True))
        box.stub("python3", python("3.9.6", fits=True))           # never reached
        r = self.run_setup(box)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), ["ok   Python 3.11.4",
                                                 f"     installing marimo {VERSION} and the usual libraries (a minute or two)",
                                                 f"ok   marimo {VERSION}"])
        self.assertIn("python3.11 -m venv .venv", box.logged())
        self.assertIn(f"python -m pip install --quiet marimo=={VERSION} numpy pandas polars altair matplotlib duckdb pyarrow", box.logged())
        self.assertFalse(any(c.startswith("python3 ") for c in box.logged()))

    def test_an_existing_venv_is_reused_and_a_failed_pip_upgrade_is_not_fatal(self):
        box = self.sandbox()
        box.stub("python3.13", python("3.13.1", fits=True))
        box.venv()
        # pip upgrade fails, the install itself succeeds
        box.stub("python", 'case "$*" in *--upgrade*) exit 1 ;; esac', where=box.install / ".venv" / "bin")
        r = self.run_setup(box)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("python3.13 -m venv .venv", box.logged())
        self.assertIn("python -m pip install --quiet --upgrade pip", box.logged())
        self.assertEqual(r.stdout.splitlines()[::2], ["ok   Python 3.13.1", f"ok   marimo {VERSION}"])

    def test_no_python_that_fits_is_a_miss(self):
        box = self.sandbox()
        box.stub("python3", python("3.14.0", fits=False))
        r = self.run_setup(box)
        self.assertEqual((r.returncode, r.stdout), (1, "miss python 3.10–3.13 (brew install python@3.12)\n"))

    def test_a_failed_install_fails_setup(self):
        box = self.sandbox()
        box.stub("python3.12", python("3.12.9", fits=True))
        box.stub("python", "exit 1", where=box.root / "template" / ".venv" / "bin")
        r = self.run_setup(box)
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("ok   marimo", r.stdout)


class InitWorkspace(unittest.TestCase):
    def test_seeds_the_verdict_with_the_venv_python(self):
        box = Sandbox(self)
        box.venv()
        ws = box.root / "ws"
        ws.mkdir()
        r = box.run("toolchain/init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.install), PIP_EXIT="1")  # a failing verdict does not stop init
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((ws / ".harness").is_dir())
        self.assertEqual(box.logged(), [f"python {box.install}/toolchain/verdict.py"])

    def test_needs_the_install_dir(self):
        box = Sandbox(self)
        r = box.run("toolchain/init-workspace.sh", cwd=box.root)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", r.stderr)


class Viewer(unittest.TestCase):
    def test_runs_viewer_py_with_the_venv_python(self):
        box = Sandbox(self)
        box.stub("python", 'echo "port=$HARNESS_VIEWER_PORT workspace=$HARNESS_WORKSPACE"', where=box.install / ".venv" / "bin")
        r = box.run("viewer.sh", cwd=box.root, HARNESS_VIEWER_PORT="4123", HARNESS_WORKSPACE="/Users/example/ws")
        self.assertEqual((r.returncode, r.stdout), (0, "port=4123 workspace=/Users/example/ws\n"), r.stderr)
        self.assertEqual(box.logged(), [f"python {box.install}/viewer.py"])

    def test_needs_a_port_and_a_workspace(self):
        box = Sandbox(self)
        for env, missing in (({"HARNESS_WORKSPACE": "/Users/example/ws"}, "HARNESS_VIEWER_PORT"), ({"HARNESS_VIEWER_PORT": "4123"}, "HARNESS_WORKSPACE")):
            with self.subTest(missing=missing):
                r = box.run("viewer.sh", **env)
                self.assertNotEqual(r.returncode, 0)
                self.assertIn(missing, r.stderr)
                self.assertEqual(box.logged(), [])


if __name__ == "__main__":
    unittest.main()
