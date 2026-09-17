"""setup.sh, doctor.sh and init-workspace.sh, run for real against a scratch install whose PATH holds
only stub commands (and the few coreutils the scripts use), so every ok / warn / miss line is reached
without a network, a Python 3.11 or a 300 MB bpy wheel:

    python3 -m unittest toolchain/test_scripts.py
"""
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent
# A bash line tracer (BASH_ENV sourcing a DEBUG trap that appends to SHCOV_OUT) is passed through when set.
TRACER = {k: os.environ[k] for k in ("BASH_ENV", "SHCOV_OUT") if k in os.environ}
BASH = "/bin/bash"
COREUTILS = ("dirname", "cat", "mkdir", "cp", "rm", "chmod", "grep")
VERSION = (PACKAGE / "BPY_VERSION").read_text().strip()

# The venv's python: answers the bpy import (IMPORT_BPY), its version string, pip (PIP_EXIT; the pip
# self-upgrade always fails, which setup tolerates) and the heredoc render check (RENDER_EXIT).
VENV_PYTHON = """case "$1" in
  -c) case "$2" in *version_string*) echo "%s" ;; *) exit "${IMPORT_BPY:-0}" ;; esac ;;
  -m) case "$*" in *--upgrade*) exit 1 ;; *) exit "${PIP_EXIT:-0}" ;; esac ;;
  -) cat >/dev/null; [ "${RENDER_EXIT:-0}" = 0 ] || exit "$RENDER_EXIT"; echo "ok   headless rendering works" ;;
esac""" % VERSION


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
            (self.install / "toolchain" / script.name).symlink_to(script)  # linked, not copied: a line tracer maps back to the source
        shutil.copy(PACKAGE / "BPY_VERSION", self.install / "BPY_VERSION")
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

    def interpreter(self, name: str, version: str) -> Path:
        """A python on PATH: the 3.11 probe answers for `version`; `-m venv` makes a venv of stubs."""
        venv_python = self.stub("python", VENV_PYTHON, where=self.root / "templates")
        return self.stub(name, f"""case "$1" in
  -c) [ "{version[:4]}" = 3.11 ] ;;
  --version) echo "Python {version}" ;;
  -m) mkdir -p "$3/bin" && cp "{venv_python}" "$3/bin/python" ;;
esac""")

    def venv(self) -> Path:
        return self.stub("python", VENV_PYTHON, where=self.install / ".venv" / "bin")

    def run(self, script: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run([BASH, str(self.install / "toolchain" / script)], cwd=cwd or self.install,
                              env={"PATH": str(self.bin), "CALLS": str(self.calls), **TRACER, **env},
                              capture_output=True, text=True, timeout=60)

    def logged(self) -> list[str]:
        return self.calls.read_text().splitlines()


class Doctor(unittest.TestCase):
    def test_ready_with_ffmpeg(self):
        box = Sandbox(self)
        box.venv()
        box.stub("ffmpeg")
        r = box.run("doctor.sh")
        self.assertEqual((r.returncode, r.stdout.splitlines()), (0, [f"ok   blender {VERSION}", "ok   ffmpeg (turntables)"]), r.stderr)

    def test_no_ffmpeg_is_only_a_warning(self):
        box = Sandbox(self)
        box.venv()
        r = box.run("doctor.sh")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout.splitlines()[-1], "warn ffmpeg not on PATH — turntables stay as frames (brew install ffmpeg)")

    def test_no_venv_is_a_miss_and_stops(self):
        box = Sandbox(self)
        box.stub("ffmpeg")
        r = box.run("doctor.sh")
        self.assertEqual((r.returncode, r.stdout.splitlines()), (1, ["miss .venv with bpy — run toolchain/setup.sh"]))

    def test_a_venv_without_bpy_is_a_miss(self):
        box = Sandbox(self)
        box.venv()
        r = box.run("doctor.sh", IMPORT_BPY="1")
        self.assertEqual((r.returncode, r.stdout.splitlines()), (1, ["miss .venv with bpy — run toolchain/setup.sh"]))


class Setup(unittest.TestCase):
    def test_installs_bpy_into_a_venv_and_checks_rendering(self):
        box = Sandbox(self)
        box.interpreter("python3.11", "3.11.9")
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            "ok   Python 3.11.9",
            f"     installing bpy {VERSION} (Blender as a module, ~300 MB, a few minutes the first time)",
            f"ok   blender {VERSION}",
            "     render check (Workbench, headless)",
            "ok   headless rendering works",
        ])
        log = box.logged()
        self.assertIn("python3.11 -m venv .venv", log)
        self.assertIn(f"python -m pip install --quiet bpy=={VERSION} numpy", log)
        self.assertEqual(log[-1], "python -")

    def test_python3_serves_when_it_is_3_11(self):
        box = Sandbox(self)
        box.interpreter("python3", "3.11.2")
        r = box.run("setup.sh")
        self.assertEqual((r.returncode, r.stdout.splitlines()[0]), (0, "ok   Python 3.11.2"))
        self.assertIn("python3 -m venv .venv", box.logged())

    def test_a_python3_11_that_is_another_version_is_passed_over(self):
        box = Sandbox(self)
        box.interpreter("python3.11", "3.12.0")
        box.interpreter("python3", "3.11.4")
        r = box.run("setup.sh")
        self.assertEqual((r.returncode, r.stdout.splitlines()[0]), (0, "ok   Python 3.11.4"))

    def test_no_python_3_11_is_a_miss(self):
        box = Sandbox(self)
        box.interpreter("python3", "3.12.1")
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.strip(), f"miss python 3.11 exactly — the bpy {VERSION} wheel is built for it (brew install python@3.11)")

    def test_an_existing_venv_is_reused(self):
        box = Sandbox(self)
        box.interpreter("python3.11", "3.11.9")
        box.venv()
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("python3.11 -m venv .venv", box.logged())

    def test_a_failed_install_stops_setup(self):
        box = Sandbox(self)
        box.interpreter("python3.11", "3.11.9")
        r = box.run("setup.sh", PIP_EXIT="1")
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn(f"ok   blender {VERSION}", r.stdout)

    def test_a_render_check_that_fails_fails_setup(self):
        box = Sandbox(self)
        box.interpreter("python3.11", "3.11.9")
        r = box.run("setup.sh", RENDER_EXIT="3")
        self.assertEqual(r.returncode, 3)
        self.assertEqual(r.stdout.splitlines()[-1], "     render check (Workbench, headless)")


class InitWorkspace(unittest.TestCase):
    def test_builds_the_starter_and_seeds_the_verdict(self):
        box = Sandbox(self)
        ws = box.root / "ws"
        ws.mkdir()
        # Both fail: a starter that cannot build (no bpy yet) must not stop the workspace being made.
        box.stub("python", 'echo "PYTHONPATH=${PYTHONPATH:-}" >> "$CALLS"; exit 1', where=box.install / ".venv" / "bin")
        r = box.run("init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.install))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((ws / ".harness").is_dir() and (ws / "out").is_dir())
        self.assertEqual(box.logged(), ["python scenes/hello.py", f"PYTHONPATH={box.install}/toolchain",
                                        f"python {box.install}/toolchain/verdict.py", "PYTHONPATH="])

    def test_needs_the_install_dir(self):
        box = Sandbox(self)
        r = box.run("init-workspace.sh", cwd=box.root)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", r.stderr)


if __name__ == "__main__":
    unittest.main()
