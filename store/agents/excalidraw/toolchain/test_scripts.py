"""setup.sh, doctor.sh, init-workspace.sh and viewer.sh, run for real against a scratch install whose
PATH holds only stub commands (and the few coreutils the scripts use), so every ok / miss line and
exit path is reached without npm, a network or the installed node_modules:

    python3 -m unittest toolchain/test_scripts.py
"""
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent
# A bash line tracer (BASH_ENV sourcing a DEBUG trap that appends to SHCOV_OUT) is passed through when set.
TRACER = {k: os.environ[k] for k in ("BASH_ENV", "SHCOV_OUT") if k in os.environ}
BASH = "/bin/bash"
COREUTILS = ("dirname", "mkdir")
BUNDLE = "node_modules/@excalidraw/excalidraw/dist/excalidraw.production.min.js"
# `node -p "require(...)"`: the versions the scripts print.
NODE = 'case "$2" in *react/package.json*) echo 18.3.1 ;; *) echo 0.17.6 ;; esac'


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
        (self.install / "viewer.sh").symlink_to(PACKAGE / "viewer.sh")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls.log"
        self.calls.touch()
        for name in COREUTILS:
            real = next(p for p in (Path("/bin") / name, Path("/usr/bin") / name) if p.exists())
            (self.bin / name).symlink_to(real)

    def stub(self, name: str, body: str = "") -> Path:
        path = self.bin / name
        path.write_text(f'#!/bin/bash\necho "{name} $*" >> "$CALLS"\n{body}\n')
        path.chmod(0o755)
        return path

    def file(self, rel: str) -> None:
        path = self.install / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("")

    def run(self, script: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run([BASH, str(self.install / script)], cwd=cwd or self.install,
                              env={"PATH": str(self.bin), "CALLS": str(self.calls), **TRACER, **env},
                              capture_output=True, text=True, timeout=60)

    def logged(self) -> list[str]:
        return self.calls.read_text().splitlines()


class Doctor(unittest.TestCase):
    def test_ready(self):
        box = Sandbox(self)
        box.stub("node", NODE)
        box.stub("python3", 'echo "Python 3.12.1"')
        for rel in (BUNDLE, "viewer.mjs", "viewer/index.html", "viewer/app.js"):
            box.file(rel)
        r = box.run("toolchain/doctor.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), ["ok   excalidraw 0.17.6", "ok   pane (viewer.mjs, viewer/)", "ok   Python 3.12.1"])

    def test_every_miss_is_reported_not_just_the_first(self):
        box = Sandbox(self)
        r = box.run("toolchain/doctor.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines(), ["miss node_modules — run toolchain/setup.sh",
                                                 "miss viewer.mjs or viewer/ — the checkout is incomplete",
                                                 "miss python3"])

    def test_a_pane_missing_one_file_is_incomplete(self):
        box = Sandbox(self)
        box.stub("node", NODE)
        box.stub("python3", 'echo "Python 3.12.1"')
        for rel in (BUNDLE, "viewer.mjs", "viewer/index.html"):
            box.file(rel)
        r = box.run("toolchain/doctor.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[1], "miss viewer.mjs or viewer/ — the checkout is incomplete")


class Setup(unittest.TestCase):
    def sandbox(self, *missing: str, npm: str = f"mkdir -p node_modules/@excalidraw/excalidraw/dist && : > {BUNDLE}") -> Sandbox:
        box = Sandbox(self)
        for name, body in (("node", NODE), ("npm", npm), ("python3", "")):
            if name not in missing:
                box.stub(name, body)
        return box

    def test_installs_from_the_lockfile(self):
        box = self.sandbox()
        r = box.run("toolchain/setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), ["     npm ci (Excalidraw 0.17.6)", "ok   excalidraw 0.17.6 · react 18.3.1"])
        self.assertIn("npm ci --silent --no-audit --no-fund", box.logged())

    def test_each_missing_tool_is_a_miss(self):
        for tool, line in (("node", "miss node >= 18 on PATH"), ("npm", "miss npm on PATH"),
                           ("python3", "miss python3 (the scene helper and the verdict)")):
            with self.subTest(tool=tool):
                r = self.sandbox(tool).run("toolchain/setup.sh")
                self.assertEqual((r.returncode, r.stdout.strip()), (1, line))

    def test_a_failed_npm_ci_fails_setup(self):
        r = self.sandbox(npm="exit 1").run("toolchain/setup.sh")
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("ok", r.stdout)

    def test_no_bundle_after_npm_ci_is_a_miss(self):
        r = self.sandbox(npm="true").run("toolchain/setup.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[-1], "miss the Excalidraw bundle after npm ci")


class InitWorkspace(unittest.TestCase):
    def test_seeds_the_verdict_and_survives_a_failing_one(self):
        box = Sandbox(self)
        ws = box.root / "ws"
        ws.mkdir()
        box.stub("python3", "exit 1")
        r = box.run("toolchain/init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.install))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((ws / ".harness").is_dir())
        self.assertEqual(box.logged(), [f"python3 {box.install}/toolchain/verdict.py"])

    def test_needs_the_install_dir(self):
        r = Sandbox(self).run("toolchain/init-workspace.sh")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", r.stderr)


class Viewer(unittest.TestCase):
    def test_runs_the_server_beside_it(self):
        box = Sandbox(self)
        box.stub("node", 'echo "port $HARNESS_VIEWER_PORT"')
        r = box.run("viewer.sh", cwd=box.root, HARNESS_VIEWER_PORT="4123", HARNESS_WORKSPACE=str(box.root))
        self.assertEqual((r.returncode, r.stdout), (0, "port 4123\n"), r.stderr)
        self.assertEqual(box.logged(), [f"node {box.install}/viewer.mjs"])

    def test_needs_a_port_and_a_workspace(self):
        box = Sandbox(self)
        box.stub("node")
        for env, missing in (({"HARNESS_WORKSPACE": "/tmp"}, "HARNESS_VIEWER_PORT"), ({"HARNESS_VIEWER_PORT": "4123"}, "HARNESS_WORKSPACE")):
            with self.subTest(missing=missing):
                r = box.run("viewer.sh", **env)
                self.assertNotEqual(r.returncode, 0)
                self.assertIn(missing, r.stderr)
        self.assertEqual(box.logged(), [], "node never starts")


if __name__ == "__main__":
    unittest.main()
