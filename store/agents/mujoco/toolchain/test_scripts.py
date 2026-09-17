"""setup.sh, doctor.sh, init-workspace.sh and install-training.sh, run for real against a scratch
install whose PATH holds only stub commands (and the few coreutils the scripts use): every ok / miss /
warn line is reached with no network, no pip and no MuJoCo on the machine.

    python3 -m unittest toolchain/test_scripts.py
"""
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent
# A bash line tracer (BASH_ENV sourcing a DEBUG trap that appends to SHCOV_OUT) is passed through when set.
TRACER = {k: os.environ[k] for k in ("BASH_ENV", "SHCOV_OUT") if k in os.environ}
BASH = "/bin/bash"
COREUTILS = ("dirname", "cat", "mkdir", "cp", "rm", "grep")
VERSIONS = dict(line.split("=", 1) for line in (PACKAGE / "VERSIONS").read_text().split("\n") if "=" in line)
MUJOCO = VERSIONS["MUJOCO"]
COMMIT = VERSIONS["MENAGERIE_COMMIT"]
ROBOTS = VERSIONS["MENAGERIE_ROBOTS"].strip('"').split()

# The venv's python: pip succeeds unless told otherwise, `import mujoco` works, the training imports
# only when TRAINING=1, and the heredoc render check "renders" when it is the script it should be.
VENV_PYTHON = r'''
case "$1" in
  -m) case " $* " in
        *" --upgrade pip "*) exit "${PIP_UPGRADE_EXIT:-0}" ;;
        *) exit "${PIP_EXIT:-0}" ;;
      esac ;;
  -c) case "$2" in
        *jax*) [ "${TRAINING:-0}" = 1 ] || exit 1
               case "$2" in *print*) echo "ok   jax 0.7.2 · mjx · playground 0.2.0 · devices [CpuDevice(id=0)]" ;; esac ;;
        *__version__*) echo "$MUJOCO_VERSION" ;;
        *) exit "${IMPORT_EXIT:-0}" ;;
      esac ;;
  -) cat > "$CALLS.stdin"
     grep -q "mujoco.Renderer(m, 64, 64)" "$CALLS.stdin" && [ "${GL:-1}" = 1 ] || exit 1
     echo "ok   offscreen rendering works" ;;
  *) echo "env PYTHONPATH=${PYTHONPATH-} MENAGERIE=${MENAGERIE-}" >> "$CALLS"; exit "${RUN_EXIT:-0}" ;;
esac
'''

# A system python: passes the version probe unless PROBE_EXIT says otherwise, and makes a venv.
SYSTEM_PYTHON = r'''
case "$1" in
  -c) exit "${PROBE_EXIT:-0}" ;;
  --version) echo "Python ${VERSION:-3.12.4}" ;;
  -m) mkdir -p "$3/bin" && cp "$VENV_TEMPLATE" "$3/bin/python" ;;
esac
'''

# git, as far as setup.sh uses it: the sparse set is remembered, checkout lays those robots out.
GIT = r'''
case "$1" in
  sparse-checkout) if [ "$2" = set ]; then shift 2; echo "$*" > .sparse; fi ;;
  fetch) exit "${FETCH_EXIT:-0}" ;;
  checkout) for r in $(cat .sparse); do
              if [ "$r" != "${SKIP_ROBOT:-}" ]; then mkdir -p "$r"; echo "<mujoco/>" > "$r/scene.xml"; fi
            done ;;
esac
'''


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
        shutil.copy(PACKAGE / "VERSIONS", self.install / "VERSIONS")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls.log"
        self.calls.touch()
        for name in COREUTILS:
            real = next(p for p in (Path("/bin") / name, Path("/usr/bin") / name) if p.exists())
            (self.bin / name).symlink_to(real)
        self.venv_template = self.stub("python", VENV_PYTHON, where=self.root / "templates")

    def stub(self, name: str, body: str = "", where: Path | None = None) -> Path:
        path = (where or self.bin) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f'#!/bin/bash\necho "{name} $*" >> "$CALLS"\n{body}\n')
        path.chmod(0o755)
        return path

    def venv(self) -> None:
        (self.install / ".venv" / "bin").mkdir(parents=True)
        shutil.copy(self.venv_template, self.install / ".venv" / "bin" / "python")

    def menagerie(self, commit: str = COMMIT, robots=ROBOTS) -> None:
        for robot in robots:
            (self.install / "menagerie" / robot).mkdir(parents=True)
            (self.install / "menagerie" / robot / "scene.xml").write_text("<mujoco/>")
        (self.install / "menagerie" / ".harness-commit").write_text(commit + "\n")

    def run(self, script: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run([BASH, str(self.install / "toolchain" / script)], cwd=cwd or self.install,
                              env={"PATH": str(self.bin), "CALLS": str(self.calls), "VENV_TEMPLATE": str(self.venv_template),
                                   "MUJOCO_VERSION": MUJOCO, **TRACER, **env},
                              capture_output=True, text=True, timeout=60)

    def logged(self) -> list[str]:
        return self.calls.read_text().splitlines()


class Doctor(unittest.TestCase):
    def test_ready_with_the_training_extras(self):
        box = Sandbox(self)
        box.venv()
        box.menagerie()
        r = box.run("doctor.sh", TRAINING="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [f"ok   mujoco {MUJOCO}", f"ok   menagerie @ {COMMIT}", "ok   training extras (jax, mjx, playground)"])

    def test_ready_without_them_is_a_warning_only(self):
        box = Sandbox(self)
        box.venv()
        box.menagerie()
        r = box.run("doctor.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines()[-1], "warn training extras not installed — toolchain/install-training.sh when a policy is wanted")

    def test_nothing_installed(self):
        r = Sandbox(self).run("doctor.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines(), ["miss .venv with mujoco — run toolchain/setup.sh", "miss menagerie — run toolchain/setup.sh",
                                                 "warn training extras not installed — toolchain/install-training.sh when a policy is wanted"])

    def test_a_venv_that_cannot_import_mujoco_is_a_miss(self):
        box = Sandbox(self)
        box.venv()
        box.menagerie()
        r = box.run("doctor.sh", IMPORT_EXIT="1")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[0], "miss .venv with mujoco — run toolchain/setup.sh")


class Setup(unittest.TestCase):
    def sandbox(self) -> Sandbox:
        box = Sandbox(self)
        box.stub("git", GIT)
        return box

    def test_a_fresh_install(self):
        box = self.sandbox()
        for name in ("python3", "python3.11", "python3.13"):
            box.stub(name, SYSTEM_PYTHON)
        # No python3.12: python3.11 comes next, before python3.13 and python3. A failing pip
        # self-upgrade is not fatal.
        r = box.run("setup.sh", VERSION="3.11.9", PIP_UPGRADE_EXIT="1")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            "ok   Python 3.11.9",
            f"     installing mujoco {MUJOCO}",
            f"ok   mujoco {MUJOCO}",
            f"     fetching MuJoCo Menagerie @ {COMMIT} ({' '.join(ROBOTS)})",
            f"ok   menagerie: {' '.join(ROBOTS)}",
            "     rendering check",
            "ok   offscreen rendering works",
        ])
        calls = box.logged()
        self.assertIn("python3.11 -m venv .venv", calls)
        self.assertIn(f'python -m pip install --quiet mujoco=={MUJOCO} numpy imageio[ffmpeg]', calls)
        self.assertIn(f"git sparse-checkout set {' '.join(ROBOTS)}", calls)
        self.assertIn(f"git fetch -q --depth 1 --filter=blob:none origin {COMMIT}", calls)
        self.assertFalse(any(c.startswith("python3 ") for c in calls), "python3.11 is tried before python3")
        self.assertEqual((box.install / "menagerie" / ".harness-commit").read_text().strip(), COMMIT)
        for robot in ROBOTS:
            self.assertTrue((box.install / "menagerie" / robot / "scene.xml").is_file())

    def test_a_second_run_keeps_the_venv_and_the_menagerie(self):
        box = self.sandbox()
        box.stub("python3.12", SYSTEM_PYTHON)
        box.venv()
        box.menagerie()
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn("     fetching", r.stdout)
        calls = box.logged()
        self.assertFalse(any(c.startswith("git ") for c in calls))
        self.assertNotIn("python3.12 -m venv .venv", calls)

    def test_a_menagerie_at_another_commit_is_fetched_again(self):
        box = self.sandbox()
        box.stub("python3.12", SYSTEM_PYTHON)
        box.venv()
        box.menagerie(commit="0" * 40, robots=["old_robot"])
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn(f"     fetching MuJoCo Menagerie @ {COMMIT}", r.stdout)
        self.assertFalse((box.install / "menagerie" / "old_robot").exists(), "the old checkout is replaced, not added to")

    def test_no_python_in_range_is_a_miss(self):
        box = self.sandbox()
        box.stub("python3", SYSTEM_PYTHON)
        r = box.run("setup.sh", PROBE_EXIT="1")
        self.assertEqual((r.returncode, r.stdout.strip()), (1, "miss python 3.10–3.13 (brew install python@3.12)"))

    def test_a_robot_the_checkout_did_not_bring_is_a_miss(self):
        box = self.sandbox()
        box.stub("python3.12", SYSTEM_PYTHON)
        r = box.run("setup.sh", SKIP_ROBOT=ROBOTS[-1])
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[-1], f"miss menagerie/{ROBOTS[-1]}/scene.xml")

    def test_failures_stop_setup(self):
        for env, not_reached in (({"PIP_EXIT": "1"}, "ok   mujoco"), ({"FETCH_EXIT": "128"}, "ok   menagerie"), ({"GL": "0"}, "ok   offscreen")):
            with self.subTest(**env):
                box = self.sandbox()
                box.stub("python3.12", SYSTEM_PYTHON)
                r = box.run("setup.sh", **env)
                self.assertNotEqual(r.returncode, 0)
                self.assertNotIn(not_reached, r.stdout)
                if "FETCH_EXIT" in env:
                    self.assertFalse((box.install / "menagerie" / ".harness-commit").exists(), "a failed fetch is fetched again next time")


class InstallTraining(unittest.TestCase):
    def test_installs_mjx_pinned_to_the_mujoco_setup_installed(self):
        box = Sandbox(self)
        box.venv()
        r = box.run("install-training.sh", TRAINING="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), ["ok   jax 0.7.2 · mjx · playground 0.2.0 · devices [CpuDevice(id=0)]"])
        # Before: an unpinned mujoco-mjx, which pulls the newest mujoco over the pinned one.
        self.assertIn(f"python -m pip install --quiet jax mujoco=={MUJOCO} mujoco-mjx=={MUJOCO} playground", box.logged())

    def test_a_failed_install_fails(self):
        box = Sandbox(self)
        box.venv()
        r = box.run("install-training.sh", PIP_EXIT="1", TRAINING="1")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_imports_that_do_not_work_after_install_fail(self):
        box = Sandbox(self)
        box.venv()
        r = box.run("install-training.sh")
        self.assertNotEqual(r.returncode, 0)


class InitWorkspace(unittest.TestCase):
    def test_a_first_rollout_and_the_verdict_even_when_both_fail(self):
        box = Sandbox(self)
        box.venv()
        ws = box.root / "ws"
        ws.mkdir()
        r = box.run("init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.install), RUN_EXIT="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((ws / ".harness").is_dir() and (ws / "out").is_dir())
        toolchain = f"{box.install}/toolchain"
        self.assertEqual(box.logged(), [
            "python sim/hello.py", f"env PYTHONPATH={toolchain} MENAGERIE={box.install}/menagerie",
            f"python {toolchain}/verdict.py", f"env PYTHONPATH={toolchain} MENAGERIE=",
        ])

    def test_needs_the_install_dir(self):
        box = Sandbox(self)
        r = box.run("init-workspace.sh", cwd=box.root)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", r.stderr)


if __name__ == "__main__":
    unittest.main()
