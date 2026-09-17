"""setup.sh, doctor.sh and viewer.sh, run against a copy of this package in a temp directory (its name
has a space, as a home directory may) with every command they call stubbed: the Python candidates,
the venv's python (which runs the real pane_client.py against test/fake_cadgen.py), and cadgen.
PATH holds only the stubs and the few system tools the scripts use, so nothing on this machine —
no real Python, no network, no pip — is touched.

    python3 -m unittest discover -s test
"""
from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
sys.path.insert(0, str(HERE))

import fake_cadgen  # noqa: E402

VENV_PYTHON = """#!/bin/sh
printf 'python %s\\n' "$*" >> "$STUB_LOG"
if [ "$1" = "-m" ] && [ "$2" = "pip" ]; then
  case " $* " in
    *" --upgrade pip "*) [ -z "$STUB_PIP_UPGRADE_FAIL" ] || exit 1 ;;
    *) [ -z "$STUB_PIP_INSTALL_FAIL" ] || { echo "ERROR: No matching distribution found for cadgen" >&2; exit 1; } ;;
  esac
  exit 0
fi
if [ "$1" = "-c" ]; then [ -z "$STUB_NO_BUILD123D" ] || exit 1; exit 0; fi
exec "$REAL_PYTHON" "$@"
"""

CADGEN = """#!/bin/sh
printf 'cadgen %s\\n' "$*" >> "$STUB_LOG"
case "$1" in
  --version|doctor)
    [ -z "$STUB_CADGEN_BROKEN" ] || exit 1
    echo "cadgen 0.5.1"
    [ "$1" = doctor ] && echo "  pin      none found (no requirements.txt to check)"
    exit 0 ;;
  viewer)
    printf 'cwd %s\\n' "$(pwd)"
    for arg in "$@"; do printf 'arg %s\\n' "$arg"; done ;;
esac
"""

# A python3.x on PATH: old enough to be skipped, or new enough to make the venv.
CANDIDATE = """#!/bin/sh
case "$1" in
  -c) exit {check} ;;
  --version) echo "Python {version}" ;;
  -m)
    printf '%s %s\\n' "$(basename "$0")" "$*" >> "$STUB_LOG"
    /bin/mkdir -p .venv/bin
    /bin/cp "$STUBS/venv-python" .venv/bin/python
    /bin/cp "$STUBS/venv-cadgen" .venv/bin/cadgen ;;
esac
"""


def executable(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return path


class ScriptTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="cad-viewer scripts "))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.pkg = self.root / "cad viewer"
        self.pkg.mkdir()
        for name in ("setup.sh", "doctor.sh", "viewer.sh", "pane_client.py", "CADGEN_VERSION"):
            shutil.copy2(PACKAGE / name, self.pkg / name)
        self.stubs = self.root / "stubs"
        self.stubs.mkdir()
        executable(self.stubs / "venv-python", VENV_PYTHON)
        executable(self.stubs / "venv-cadgen", CADGEN)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for tool in ("bash", "dirname", "basename", "cat", "head"):
            found = shutil.which(tool)
            assert found, f"{tool} is needed to run the scripts"
            (self.bin / tool).symlink_to(found)
        self.log = self.root / "calls.log"
        self.log.touch()
        self.site = fake_cadgen.make_site()
        self.addCleanup(shutil.rmtree, self.site, True)
        self.workspace = self.root / "my workspace"
        self.workspace.mkdir()

    def candidate(self, name: str, *, ok: bool, version: str) -> None:
        executable(self.bin / name, CANDIDATE.format(check=0 if ok else 1, version=version))

    def venv(self) -> None:
        """A venv as setup.sh leaves it."""
        (self.pkg / ".venv" / "bin").mkdir(parents=True)
        shutil.copy2(self.stubs / "venv-python", self.pkg / ".venv" / "bin" / "python")
        shutil.copy2(self.stubs / "venv-cadgen", self.pkg / ".venv" / "bin" / "cadgen")

    def run_script(self, script: str, *, cadgen_importable: bool = True, **env: str) -> subprocess.CompletedProcess[str]:
        base = {
            "PATH": str(self.bin), "HOME": str(self.root), "STUB_LOG": str(self.log), "STUBS": str(self.stubs),
            "REAL_PYTHON": sys.executable, "PYTHONDONTWRITEBYTECODE": "1",
        }
        if cadgen_importable:
            base["PYTHONPATH"] = str(self.site)
        return subprocess.run([str(self.pkg / script)], cwd=self.root, env={**base, **env}, capture_output=True, text=True, timeout=60)

    def calls(self) -> list[str]:
        return self.log.read_text(encoding="utf-8").splitlines()


class SetupTest(ScriptTest):
    def test_without_python_311_or_newer_it_says_what_to_install_and_fails(self) -> None:
        self.candidate("python3", ok=False, version="3.9.6")
        result = self.run_script("setup.sh")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "miss python 3.11+ (brew install python@3.12)\n")
        self.assertFalse((self.pkg / ".venv").exists())

    def test_a_fresh_install_makes_the_venv_with_the_first_new_enough_python_pins_cadgen_and_makes_the_client(self) -> None:
        self.candidate("python3.12", ok=False, version="3.12.0")  # present, but says it is too old: skipped
        self.candidate("python3.11", ok=True, version="3.11.9")
        self.candidate("python3", ok=True, version="3.13.1")
        result = self.run_script("setup.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            "ok   Python 3.11.9",
            "     installing cadgen 0.5.1 (this pulls OpenCascade; a few minutes the first time)",
            "ok   cadgen 0.5.1",
            "ok   pane client",
        ])
        self.assertEqual(self.calls()[:3], [
            "python3.11 -m venv .venv",
            "python -m pip install --quiet --upgrade pip",
            "python -m pip install --quiet cadgen==0.5.1",
        ])
        self.assertTrue((self.pkg / ".pane-client-0.5.1" / ".harness-pane").is_file())

    def test_an_existing_venv_is_kept_a_failed_pip_upgrade_is_tolerated_and_a_missing_client_is_a_warning(self) -> None:
        self.candidate("python3", ok=True, version="3.12.4")
        self.venv()
        result = self.run_script("setup.sh", cadgen_importable=False, STUB_PIP_UPGRADE_FAIL="1", STUB_CADGEN_BROKEN="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            "ok   Python 3.12.4",
            "     installing cadgen 0.5.1 (this pulls OpenCascade; a few minutes the first time)",
            "ok   cadgen 0.5.1",
            "warn pane client not made — the pane serves the bundled client",
        ])
        self.assertNotIn("python3 -m venv .venv", self.calls())
        self.assertFalse(any(p.name.startswith(".pane-client") for p in self.pkg.iterdir()))

    def test_a_failed_cadgen_install_fails_setup(self) -> None:
        self.candidate("python3.13", ok=True, version="3.13.1")
        result = self.run_script("setup.sh", STUB_PIP_INSTALL_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No matching distribution found for cadgen", result.stderr)
        self.assertNotIn("ok   cadgen", result.stdout)


class DoctorTest(ScriptTest):
    def test_before_setup_both_checks_miss(self) -> None:
        result = self.run_script("doctor.sh")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines(), ["miss .venv/bin/cadgen — run setup.sh", "miss build123d (OpenCascade) in the venv"])

    def test_after_setup_it_names_the_installed_cadgen_and_opencascade(self) -> None:
        self.venv()
        result = self.run_script("doctor.sh")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines(), ["ok   cadgen 0.5.1", "ok   build123d + OpenCascade"])
        self.assertIn("cadgen doctor .", self.calls())

    def test_a_cadgen_that_cannot_answer_falls_back_to_the_pinned_version_and_a_venv_without_build123d_misses(self) -> None:
        self.venv()
        result = self.run_script("doctor.sh", STUB_CADGEN_BROKEN="1", STUB_NO_BUILD123D="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines(), ["ok   cadgen 0.5.1", "miss build123d (OpenCascade) in the venv"])


class ViewerTest(ScriptTest):
    def viewer_args(self, result: subprocess.CompletedProcess[str]) -> tuple[Path, list[str]]:
        lines = result.stdout.splitlines()
        cwd = Path(next(line[4:] for line in lines if line.startswith("cwd ")))
        return cwd, [line[4:] for line in lines if line.startswith("arg ")]

    def test_it_needs_the_port_and_the_workspace(self) -> None:
        self.venv()
        missing_port = self.run_script("viewer.sh", HARNESS_WORKSPACE=str(self.workspace))
        self.assertNotEqual(missing_port.returncode, 0)
        self.assertIn("HARNESS_VIEWER_PORT is required", missing_port.stderr)
        missing_workspace = self.run_script("viewer.sh", HARNESS_VIEWER_PORT="4321")
        self.assertNotEqual(missing_workspace.returncode, 0)
        self.assertIn("HARNESS_WORKSPACE is required", missing_workspace.stderr)
        self.assertFalse(any(call.startswith("cadgen") for call in self.calls()))

    def test_it_serves_the_workspace_on_loopback_as_a_private_instance_with_the_pane_client(self) -> None:
        self.venv()
        result = self.run_script("viewer.sh", HARNESS_VIEWER_PORT="4321", HARNESS_WORKSPACE=str(self.workspace))
        self.assertEqual(result.returncode, 0, result.stderr)
        cwd, args = self.viewer_args(result)
        self.assertEqual(cwd.resolve(), self.workspace.resolve())
        self.assertEqual(args[:7], ["viewer", "--host", "127.0.0.1", "--port", "4321", "--new", "--no-registry"])
        self.assertEqual(args[7], "--dist")
        self.assertEqual(Path(args[8]).resolve(), (self.pkg / ".pane-client-0.5.1").resolve(), "one argument, spaces and all")
        self.assertEqual(len(args), 9)

    def test_without_a_pane_client_it_serves_the_bundled_one(self) -> None:
        self.venv()
        result = self.run_script("viewer.sh", cadgen_importable=False, HARNESS_VIEWER_PORT="4321", HARNESS_WORKSPACE=str(self.workspace))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.viewer_args(result)[1], ["viewer", "--host", "127.0.0.1", "--port", "4321", "--new", "--no-registry"])
        self.assertEqual(result.stderr, "", "pane_client.py's complaint stays out of the pane's log")

    def test_a_workspace_that_is_not_there_stops_it_before_cadgen_starts(self) -> None:
        self.venv()
        result = self.run_script("viewer.sh", HARNESS_VIEWER_PORT="4321", HARNESS_WORKSPACE=str(self.root / "gone"))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call.startswith("cadgen") for call in self.calls()))


if __name__ == "__main__":
    unittest.main()
