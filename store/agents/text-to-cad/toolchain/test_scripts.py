"""python3 -m unittest toolchain/test_scripts.py — setup.sh, doctor.sh and init-workspace.sh, without cadgen.

Each test lays out a throwaway install dir with the real scripts linked in and fake interpreters on a
PATH that holds nothing else, runs a script, and checks the lines Harness would show and the exit code.
Nothing is installed and nothing touches the network.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLCHAIN = Path(__file__).resolve().parent
PACKAGE = TOOLCHAIN.parent
CADGEN_VERSION = (PACKAGE / "CADGEN_VERSION").read_text().strip()
SYSTEM_TOOLS = ("bash", "dirname", "basename", "cat", "mkdir", "cp")

# A python that answers the version probe with $OK, prints a version, and makes a venv holding the
# fake venv python below.
CANDIDATE = """#!/bin/sh
echo "$(basename "$0") $*" >> "$LOG"
case "$1" in
  -c) exit {status} ;;
  --version) echo "Python {version}" ;;
  -m) mkdir -p "$3/bin" && cp "$FAKE_VENV_PYTHON" "$3/bin/python" ;;
esac
"""
# The venv's python: every answer is an exit code the test sets in the environment.
VENV_PYTHON = """#!/bin/sh
echo "venv-python $*" >> "$LOG"
case "$*" in
  "-m pip install --quiet --upgrade pip") exit "${PIP_UPGRADE_EXIT:-0}" ;;
  "-m pip install --quiet "*) exit "${PIP_EXIT:-0}" ;;
  "-m playwright install chromium") exit "${PLAYWRIGHT_INSTALL_EXIT:-0}" ;;
  "-c import build123d") exit "${BUILD123D_EXIT:-0}" ;;
  "-c import trimesh, scipy, rtree, networkx, lxml") exit "${EXTRAS_EXIT:-0}" ;;
  "-c from playwright.sync_api import sync_playwright") exit "${PLAYWRIGHT_EXIT:-0}" ;;
  *src/part.py) echo "cwd=$PWD" >> "$LOG"; exit "${PART_EXIT:-0}" ;;
  *toolchain/verdict.py) echo "cwd=$PWD" >> "$LOG"; exit 1 ;;
esac
exit 99
"""
CADGEN = """#!/bin/sh
echo "cadgen $*" >> "$LOG"
exit "${CADGEN_DOCTOR_EXIT:-0}"
"""


def write_exe(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)
    return path


class Scripts(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.root = self.tmp / "text-to-cad"
        (self.root / "toolchain").mkdir(parents=True)
        for name in ("setup.sh", "doctor.sh", "init-workspace.sh", "verdict.py"):
            (self.root / "toolchain" / name).symlink_to(TOOLCHAIN / name)
        shutil.copy(PACKAGE / "CADGEN_VERSION", self.root / "CADGEN_VERSION")
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for tool in SYSTEM_TOOLS:
            found = shutil.which(tool)
            self.assertIsNotNone(found, tool)
            (self.bin / tool).symlink_to(found)
        self.log = self.tmp / "log"
        self.fake_venv_python = write_exe(self.tmp / "fake-venv-python", VENV_PYTHON)

    def candidate(self, name, ok=True, version="3.12.9"):
        write_exe(self.bin / name, CANDIDATE.format(status=0 if ok else 1, version=version))

    def venv(self, cadgen=True):
        write_exe(self.root / ".venv" / "bin" / "python", VENV_PYTHON)
        if cadgen:
            write_exe(self.root / ".venv" / "bin" / "cadgen", CADGEN)

    def run_script(self, name, cwd=None, **env):
        clean = {k: v for k, v in os.environ.items() if not k.startswith(("HARNESS_", "CADGEN", "TEXT_TO_CAD_"))}
        clean.update(PATH=str(self.bin), LOG=str(self.log), FAKE_VENV_PYTHON=str(self.fake_venv_python), **env)
        return subprocess.run([str(self.root / "toolchain" / name)], cwd=cwd or self.tmp, env=clean,
                              capture_output=True, text=True, timeout=60)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    # setup.sh

    def test_setup_takes_the_first_python_that_is_3_11_or_newer_and_installs_the_pinned_cadgen(self):
        self.candidate("python3.13", ok=False)
        self.candidate("python3.12")
        self.candidate("python3")
        run = self.run_script("setup.sh")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(run.stdout.splitlines(), [
            "ok   Python 3.12.9",
            f"     installing cadgen {CADGEN_VERSION} and the skills' extras (OpenCascade comes with it; minutes the first time)",
            f"ok   cadgen {CADGEN_VERSION}",
            "     installing the browser snapshots render with",
            "ok   chromium for snapshots",
        ])
        calls = self.calls()
        self.assertIn("python3.12 -m venv .venv", calls)
        self.assertFalse(any(c.startswith("python3 ") for c in calls), calls)
        self.assertIn(f"venv-python -m pip install --quiet cadgen[snapshot]=={CADGEN_VERSION} trimesh numpy scipy rtree networkx lxml", calls)
        self.assertTrue((self.root / ".venv" / "bin" / "python").exists())

    def test_setup_without_a_new_enough_python_says_so(self):
        self.candidate("python3", ok=False, version="3.9.6")
        run = self.run_script("setup.sh")
        self.assertEqual(run.returncode, 1)
        self.assertEqual(run.stdout, "miss python 3.11+ (brew install python@3.12)\n")
        self.assertFalse((self.root / ".venv").exists())

    def test_setup_reuses_a_venv_and_survives_a_pip_self_upgrade_failure(self):
        self.candidate("python3")
        self.venv(cadgen=False)
        run = self.run_script("setup.sh", PIP_UPGRADE_EXIT="1")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertNotIn("python3 -m venv .venv", self.calls())
        self.assertIn(f"ok   cadgen {CADGEN_VERSION}", run.stdout)

    def test_setup_stops_when_cadgen_does_not_install(self):
        self.candidate("python3")
        run = self.run_script("setup.sh", PIP_EXIT="1")
        self.assertNotEqual(run.returncode, 0)
        self.assertNotIn("ok   cadgen", run.stdout)
        self.assertNotIn("chromium", run.stdout)

    def test_setup_warns_when_the_snapshot_browser_does_not_install(self):
        self.candidate("python3")
        run = self.run_script("setup.sh", PLAYWRIGHT_INSTALL_EXIT="1")
        self.assertEqual(run.returncode, 0)
        self.assertEqual(run.stdout.splitlines()[-1],
                         "warn chromium for snapshots did not install; `cadgen … snapshot` will not render until "
                         "`.venv/bin/python -m playwright install chromium` succeeds")

    # doctor.sh

    def test_doctor_on_a_complete_install(self):
        self.venv()
        run = self.run_script("doctor.sh")
        self.assertEqual(run.returncode, 0)
        self.assertEqual(run.stdout.splitlines(), [
            f"ok   cadgen {CADGEN_VERSION}",
            "ok   cadgen matches the skills' pin",
            "ok   build123d + OpenCascade",
            "ok   dfam-check extras",
            "ok   playwright for snapshots",
        ])
        self.assertIn("cadgen doctor skills/cad", self.calls())

    def test_doctor_before_setup_misses_everything(self):
        run = self.run_script("doctor.sh")
        self.assertEqual(run.returncode, 1)
        self.assertEqual(run.stdout.splitlines(), [
            "miss .venv/bin/cadgen — run toolchain/setup.sh",
            "miss cadgen does not match skills/cad/requirements.txt",
            "miss build123d in the venv",
            "warn dfam-check extras missing (trimesh, scipy, rtree, networkx, lxml)",
            "warn playwright missing; snapshots will not render",
        ])

    def test_doctor_fails_on_a_cadgen_that_does_not_match_the_pin(self):
        self.venv()
        run = self.run_script("doctor.sh", CADGEN_DOCTOR_EXIT="1")
        self.assertEqual(run.returncode, 1)
        self.assertIn("miss cadgen does not match skills/cad/requirements.txt", run.stdout.splitlines())

    def test_doctor_only_warns_for_the_extras_and_the_browser(self):
        self.venv()
        run = self.run_script("doctor.sh", EXTRAS_EXIT="1", PLAYWRIGHT_EXIT="1")
        self.assertEqual(run.returncode, 0)
        self.assertEqual(run.stdout.splitlines()[3:], [
            "warn dfam-check extras missing (trimesh, scipy, rtree, networkx, lxml)",
            "warn playwright missing; snapshots will not render",
        ])

    # init-workspace.sh

    def workspace(self):
        ws = self.tmp / "ws"
        shutil.copytree(PACKAGE / "template", ws)
        return ws

    def test_init_needs_the_install_dir(self):
        ws = self.workspace()
        run = self.run_script("init-workspace.sh", cwd=ws)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR is required", run.stderr)
        self.assertFalse((ws / ".harness").exists())

    def test_init_builds_the_starter_and_seeds_the_verdict_even_when_both_fail(self):
        ws = self.workspace()
        self.venv()
        run = self.run_script("init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(self.root), PART_EXIT="1")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, "")
        for made in (".harness", "STEP", "tmp"):
            self.assertTrue((ws / made).is_dir(), made)
        self.assertEqual(self.calls(), [
            "venv-python src/part.py", f"cwd={ws.resolve()}",
            f"venv-python {self.root}/toolchain/verdict.py", f"cwd={ws.resolve()}",
        ])

    def test_init_seeds_a_real_verdict_the_header_can_show(self):
        ws = self.workspace()
        # The venv python is this python for the verdict (no cadgen: no STEP is judged) and fails the build.
        write_exe(self.root / ".venv" / "bin" / "python",
                  f'#!/bin/sh\ncase "$1" in *verdict.py) exec "{sys.executable}" "$@" ;; esac\nexit 1\n')
        run = self.run_script("init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(self.root))
        self.assertEqual(run.returncode, 0, run.stderr)
        verdict = json.loads((ws / ".harness" / "verdict.json").read_text())
        self.assertEqual((verdict["ready"], verdict["summary"]), (False, "no STEP yet"))
        self.assertEqual([p["state"] for p in verdict["phases"]], ["done", "active", "pending"])


if __name__ == "__main__":
    unittest.main()
