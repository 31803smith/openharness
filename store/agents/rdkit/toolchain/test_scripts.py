"""python3 -m unittest toolchain/test_scripts.py — setup, doctor, workspace init and the viewer launcher.

Each test builds a package root in a temp dir with this checkout's scripts symlinked in file by file and
runs them with PATH set to a bin dir holding only what the test grants: a few system tools linked in, and
stubs written here for python, the venv's python, node and npm. So "miss node" is a PATH without node,
pip and npm never run, and nothing is written into this checkout.

With RDKIT_PYTHON pointing at a Python that has RDKit, two more tests run the real chemistry: setup's
own check against this checkout's harness_rdkit.py, and init on the template (the starter molecule and
its verdict). pip still never runs; that Python is only read.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = HERE.parent
VERSIONS = dict(line.split("=", 1) for line in (PKG / "VERSIONS").read_text().split() if "=" in line)
REAL_PYTHON = os.environ.get("RDKIT_PYTHON", "")
HAS_REAL_PYTHON = bool(REAL_PYTHON) and os.access(REAL_PYTHON, os.X_OK)
TOOLS = ("bash", "cat", "dirname", "ln", "mkdir")

# The venv's python: pip is logged and never run; the import probes answer from STUB_* variables; the
# chemistry check (a script on stdin) and file runs are logged, or handed to STUB_REAL_PYTHON.
VENV_PYTHON = r"""#!/bin/bash
log() { printf '%s\n' "$*" >> "$STUB_LOG"; }
if [ "$1" = "-m" ] && [ "$2" = "pip" ]; then log "python $*"; [ "$4" = "--upgrade" ] && exit "${STUB_PIP_UPGRADE_EXIT:-0}"; exit "${STUB_PIP_EXIT:-0}"; fi
if [ -n "${STUB_REAL_PYTHON:-}" ]; then exec "$STUB_REAL_PYTHON" "$@"; fi
case "$1:$2" in
  "-c:import rdkit") exit "${STUB_RDKIT_EXIT:-0}" ;;
  "-c:import pandas") exit "${STUB_PANDAS_EXIT:-0}" ;;
  "-c:import rdkit; print(rdkit.__version__)") echo 2026.03.6 ;;
  "-c:import numpy; print(numpy.__version__)") echo 2.5.3 ;;
  "-c:import pandas; print(pandas.__version__)") echo 3.0.5 ;;
  -:*) script="$(cat)"; log "python - PYTHONPATH=$PYTHONPATH"
       case "$script" in *"from harness_rdkit import design"*) ;; *) exit 3 ;; esac
       [ "${STUB_CHEM_EXIT:-0}" = 0 ] || { echo "AssertionError" >&2; exit "$STUB_CHEM_EXIT"; }
       echo "ok   chemistry (stub)" ;;
  *) log "python $* PYTHONPATH=$PYTHONPATH cwd=$PWD"; exit "${STUB_RUN_EXIT:-0}" ;;
esac
"""

NODE = r"""#!/bin/bash
case "$1" in
  --version) echo v22.1.0 ;;
  -p) case "$2" in *"dependencies['3dmol']"*|*"3dmol/package.json"*) echo 2.5.5 ;; *) exit 9 ;; esac ;;
  *) printf 'node %s cwd=%s port=%s workspace=%s\n' "$*" "$PWD" "$HARNESS_VIEWER_PORT" "$HARNESS_WORKSPACE" ;;
esac
"""

NPM = r"""#!/bin/bash
printf 'npm %s\n' "$*" >> "$STUB_LOG"
[ -n "${STUB_NPM_NO_BUNDLE:-}" ] || { mkdir -p node_modules/3dmol/build; : > node_modules/3dmol/build/3Dmol-min.js; }
"""


def system_python(ok: bool) -> str:
    """A python3.x on PATH: its version probe passes or fails; `-m venv` lays out the stub venv."""
    return f"""#!/bin/bash
case "$1" in
  -c) exit {0 if ok else 1} ;;
  --version) echo "Python 3.12.10" ;;
  -m) printf '%s\\n' "${{0##*/}} $*" >> "$STUB_LOG"; mkdir -p "$3/bin"; ln -s "$STUB_VENV_PYTHON" "$3/bin/python" ;;
esac
"""


class Sandbox:
    def __init__(self, test: unittest.TestCase) -> None:
        tmp = tempfile.TemporaryDirectory()
        test.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name).resolve()
        self.root = self.dir / "rdkit"
        self.bin = self.dir / "bin"
        self.stubs = self.dir / "stubs"
        self.log = self.dir / "log"
        for folder in (self.root / "toolchain", self.bin, self.stubs):
            folder.mkdir(parents=True)
        self.log.write_text("")
        for tool in TOOLS:
            self.grant(tool)
        self.venv_python = self.write(self.stubs / "venv-python", VENV_PYTHON)

    @staticmethod
    def write(path: Path, text: str) -> Path:
        # Never through a link: a granted tool or a linked package file is the real one, not the sandbox's.
        assert not path.is_symlink(), f"{path} is a link; writing or chmod-ing it would change what it points at"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)
        return path

    def link(self, *rels: str) -> None:
        for rel in rels:
            (self.root / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.root / rel).symlink_to(PKG / rel)

    def grant(self, tool: str) -> None:
        found = shutil.which(tool)
        assert found, f"{tool} is needed on this machine to run the test"
        (self.bin / tool).symlink_to(found)

    def stub(self, name: str, text: str) -> None:
        self.write(self.bin / name, text)

    def venv(self) -> None:
        (self.root / ".venv" / "bin").mkdir(parents=True)
        (self.root / ".venv" / "bin" / "python").symlink_to(self.venv_python)

    def touch(self, *rels: str) -> None:
        for rel in rels:
            self.write(self.root / rel, "")

    def run(self, rel: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        clean = {k: v for k, v in os.environ.items() if not k.startswith(("HARNESS_", "RDKIT_", "PYTHON"))}
        return subprocess.run([str(self.root / rel)], cwd=cwd or self.dir, capture_output=True, text=True, timeout=120,
                              env={**clean, "PATH": str(self.bin), "STUB_LOG": str(self.log),
                                   "STUB_VENV_PYTHON": str(self.venv_python), **env})

    def logged(self) -> list[str]:
        return self.log.read_text().splitlines()


def lines(done: subprocess.CompletedProcess) -> list[str]:
    return done.stdout.splitlines()


class Setup(unittest.TestCase):
    def sandbox(self, pythons: dict[str, bool] | None = None, node: bool = True, npm: bool = True) -> Sandbox:
        box = Sandbox(self)
        box.link("toolchain/setup.sh", "VERSIONS", "package.json")
        box.touch("pane/index.html", "pane/app.js")
        for name, ok in (pythons if pythons is not None else {"python3.12": True}).items():
            box.stub(name, system_python(ok))
        if node:
            box.stub("node", NODE)
        if npm:
            box.stub("npm", NPM)
        return box

    def test_a_python_between_3_10_and_3_13_is_required(self) -> None:
        done = self.sandbox(pythons={}).run("toolchain/setup.sh")
        self.assertEqual((done.returncode, lines(done)), (1, ["miss python 3.10–3.13 (brew install python@3.12)"]))
        done = self.sandbox(pythons={"python3.12": False, "python3.13": False}).run("toolchain/setup.sh")
        self.assertEqual((done.returncode, lines(done)), (1, ["miss python 3.10–3.13 (brew install python@3.12)"]))

    def test_everything_installs_into_the_package_and_is_checked(self) -> None:
        box = self.sandbox(pythons={"python3.12": False, "python3": True})
        done = box.run("toolchain/setup.sh")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(lines(done), [
            "ok   Python 3.12.10",
            f"     installing rdkit {VERSIONS['RDKIT']}",
            "ok   rdkit 2026.03.6 · numpy 2.5.3 · pandas 3.0.5",
            "     chemistry check (build, conformers, depict, describe, series)",
            "ok   chemistry (stub)",
            "     npm ci (3Dmol.js 2.5.5)",
            "ok   3dmol 2.5.5",
        ])
        self.assertEqual(box.logged(), [
            "python3 -m venv .venv",
            "python -m pip install --quiet --upgrade pip",
            f"python -m pip install --quiet rdkit=={VERSIONS['RDKIT']} numpy=={VERSIONS['NUMPY']} pandas=={VERSIONS['PANDAS']}",
            f"python - PYTHONPATH={box.root}/toolchain",
            "npm ci --silent --no-audit --no-fund",
        ])

    def test_an_existing_venv_is_kept_and_a_failed_pip_upgrade_is_not_fatal(self) -> None:
        box = self.sandbox()
        box.venv()
        done = box.run("toolchain/setup.sh", STUB_PIP_UPGRADE_EXIT="1")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("python3.12 -m venv .venv", box.logged())

    def test_a_failed_install_or_chemistry_check_stops_setup(self) -> None:
        done = self.sandbox().run("toolchain/setup.sh", STUB_PIP_EXIT="1")
        self.assertNotEqual(done.returncode, 0)
        self.assertEqual(lines(done)[-1], f"     installing rdkit {VERSIONS['RDKIT']}")
        done = self.sandbox().run("toolchain/setup.sh", STUB_CHEM_EXIT="1")
        self.assertNotEqual(done.returncode, 0)
        self.assertEqual(lines(done)[-1], "     chemistry check (build, conformers, depict, describe, series)")

    def test_the_pane_needs_node_npm_the_bundle_and_its_files(self) -> None:
        done = self.sandbox(node=False).run("toolchain/setup.sh")
        self.assertEqual((done.returncode, lines(done)[-1]), (1, "miss node >= 18 on PATH (the pane)"))
        done = self.sandbox(npm=False).run("toolchain/setup.sh")
        self.assertEqual((done.returncode, lines(done)[-1]), (1, "miss npm on PATH (the pane)"))
        done = self.sandbox().run("toolchain/setup.sh", STUB_NPM_NO_BUNDLE="1")
        self.assertEqual((done.returncode, lines(done)[-1]), (1, "miss the 3Dmol.js bundle after npm ci"))
        box = self.sandbox()
        (box.root / "pane" / "app.js").unlink()
        done = box.run("toolchain/setup.sh")
        self.assertEqual((done.returncode, lines(done)[-1]), (1, "miss the pane (pane/index.html, pane/app.js)"))

    @unittest.skipUnless(HAS_REAL_PYTHON, "RDKIT_PYTHON is not set to a Python with RDKit")
    def test_the_chemistry_check_passes_on_this_checkouts_helper(self) -> None:
        box = self.sandbox()
        box.link("toolchain/harness_rdkit.py")
        done = box.run("toolchain/setup.sh", STUB_REAL_PYTHON=REAL_PYTHON)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("ok   conformer search, MMFF minimisation, Gasteiger charges, 2D depiction and the series work", lines(done))


class Doctor(unittest.TestCase):
    def test_a_complete_install_is_ready(self) -> None:
        box = Sandbox(self)
        box.link("toolchain/doctor.sh")
        box.venv()
        box.stub("node", NODE)
        box.touch("node_modules/3dmol/build/3Dmol-min.js", "pane/index.html", "pane/app.js")
        done = box.run("toolchain/doctor.sh")
        self.assertEqual((done.returncode, lines(done)), (0, [
            "ok   rdkit 2026.03.6",
            "ok   pandas 3.0.5 · numpy 2.5.3",
            "ok   node v22.1.0 (the pane's server)",
            "ok   3dmol 2.5.5 (the pane)",
            "ok   pane (3D, 2D, properties, conformers, series)",
        ]))

    def test_an_empty_install_says_what_is_missing(self) -> None:
        box = Sandbox(self)
        box.link("toolchain/doctor.sh")
        done = box.run("toolchain/doctor.sh")
        self.assertEqual((done.returncode, lines(done)), (1, [
            "miss .venv with rdkit — run toolchain/setup.sh",
            "warn pandas/numpy missing — tables and enumerations need them",
            "miss node >= 18 on PATH — the pane cannot start",
            "miss node_modules — run toolchain/setup.sh",
            "miss pane/ — reinstall the package",
        ]))

    def test_a_venv_without_rdkit_or_pandas(self) -> None:
        box = Sandbox(self)
        box.link("toolchain/doctor.sh")
        box.venv()
        done = box.run("toolchain/doctor.sh", STUB_RDKIT_EXIT="1", STUB_PANDAS_EXIT="1")
        self.assertEqual(lines(done)[:2], ["miss .venv with rdkit — run toolchain/setup.sh",
                                           "warn pandas/numpy missing — tables and enumerations need them"])
        self.assertEqual(done.returncode, 1)


class InitWorkspace(unittest.TestCase):
    def test_it_needs_the_install_dir(self) -> None:
        box = Sandbox(self)
        box.link("toolchain/init-workspace.sh")
        done = box.run("toolchain/init-workspace.sh")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", done.stderr)

    def test_it_builds_the_starter_and_seeds_the_verdict_and_never_fails_on_them(self) -> None:
        box = Sandbox(self)
        box.link("toolchain/init-workspace.sh")
        box.venv()
        workspace = box.dir / "workspace"
        workspace.mkdir()
        done = box.run("toolchain/init-workspace.sh", cwd=workspace, HARNESS_DSH_DIR=str(box.root), STUB_RUN_EXIT="1")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue((workspace / ".harness").is_dir() and (workspace / "out").is_dir())
        path = f"PYTHONPATH={box.root}/toolchain cwd={workspace}"
        self.assertEqual(box.logged(), [f"python molecules/hello.py {path}", f"python {box.root}/toolchain/verdict.py {path}"])

    @unittest.skipUnless(HAS_REAL_PYTHON, "RDKIT_PYTHON is not set to a Python with RDKit")
    def test_the_template_starter_designs_ibuprofen_and_the_verdict_is_ready(self) -> None:
        box = Sandbox(self)
        box.link("toolchain/init-workspace.sh", "toolchain/harness_rdkit.py", "toolchain/verdict.py")
        box.venv()
        workspace = box.dir / "workspace"
        shutil.copytree(PKG / "template", workspace)
        done = box.run("toolchain/init-workspace.sh", cwd=workspace, HARNESS_DSH_DIR=str(box.root), STUB_REAL_PYTHON=REAL_PYTHON)
        self.assertEqual(done.returncode, 0, done.stderr)
        verdict = json.loads((workspace / ".harness" / "verdict.json").read_text())
        self.assertTrue(verdict["ready"], verdict)
        self.assertEqual(verdict["artifact"], "out/ibuprofen.sdf")
        self.assertTrue((workspace / "out" / "ibuprofen.conformers.sdf").is_file())


class Viewer(unittest.TestCase):
    def test_it_needs_the_port_and_the_workspace(self) -> None:
        box = Sandbox(self)
        box.link("viewer.sh")
        done = box.run("viewer.sh", HARNESS_WORKSPACE=str(box.dir))
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("HARNESS_VIEWER_PORT", done.stderr)
        done = box.run("viewer.sh", HARNESS_VIEWER_PORT="4100")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("HARNESS_WORKSPACE", done.stderr)

    def test_it_runs_the_server_beside_it(self) -> None:
        box = Sandbox(self)
        box.link("viewer.sh")
        box.stub("node", NODE)
        done = box.run("viewer.sh", HARNESS_VIEWER_PORT="4100", HARNESS_WORKSPACE=str(box.dir))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(lines(done), [f"node {box.root}/viewer.mjs cwd={box.dir} port=4100 workspace={box.dir}"])


if __name__ == "__main__":
    unittest.main()
