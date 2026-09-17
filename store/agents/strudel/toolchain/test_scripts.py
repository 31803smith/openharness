"""python3 -m unittest toolchain/test_scripts.py — setup, doctor, init and the viewer launcher.

Each test builds a package root in a temp dir with this checkout's scripts symlinked in file by file,
and runs them with PATH set to a bin dir that holds only the tools the test grants: real ones
(bash, node, python3, …) linked in, or stubs written here. So a "miss node" branch is a PATH without
node, npm is a stub that lays out node_modules or fails, and nothing touches the network or this
checkout.
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
REPL_VERSION = json.loads((PKG / "package.json").read_text())["dependencies"]["@strudel/repl"]
BASE_TOOLS = ("bash", "dirname", "mkdir")


class Sandbox:
    def __init__(self, test: unittest.TestCase, tools: tuple[str, ...] = ()) -> None:
        tmp = tempfile.TemporaryDirectory()
        test.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name).resolve()
        self.root = self.dir / "strudel"
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        (self.root / "toolchain").mkdir(parents=True)
        for tool in BASE_TOOLS + tools:
            self.grant(tool)

    def link(self, rel: str) -> None:
        (self.root / rel).symlink_to(PKG / rel)

    def grant(self, tool: str) -> None:
        found = shutil.which(tool)
        assert found, f"{tool} is needed on this machine to run the test"
        (self.bin / tool).symlink_to(found)

    def stub(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def run(self, rel: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        clean = {k: v for k, v in os.environ.items() if not k.startswith("HARNESS_")}
        return subprocess.run([str(self.root / rel)], cwd=cwd or self.dir, capture_output=True, text=True,
                              env={**clean, "PATH": str(self.bin), **env}, timeout=60)


def lines(done: subprocess.CompletedProcess) -> list[str]:
    return done.stdout.splitlines()


class Setup(unittest.TestCase):
    def sandbox(self, *tools: str) -> Sandbox:
        box = Sandbox(self, tools)
        box.link("toolchain/setup.sh")
        box.link("package.json")
        return box

    def test_node_is_required(self) -> None:
        done = self.sandbox().run("toolchain/setup.sh")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(lines(done), ["miss node >= 18 on PATH"])

    def test_npm_is_required(self) -> None:
        done = self.sandbox("node").run("toolchain/setup.sh")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(lines(done), ["miss npm on PATH"])

    def test_python3_is_required(self) -> None:
        box = self.sandbox("node")
        box.stub("npm", "exit 0\n")
        done = box.run("toolchain/setup.sh")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(lines(done), ["miss python3 (the verdict)"])

    def npm(self, box: Sandbox, body: str) -> None:
        box.stub("npm", f'echo "$PWD $*" >> "{box.dir}/npm.calls"\n' + body)

    def test_npm_ci_lays_out_the_repl(self) -> None:
        box = self.sandbox("node", "python3")
        self.npm(box, f"""mkdir -p node_modules/@strudel/repl/dist
echo 'export {{}}' > node_modules/@strudel/repl/dist/index.js
echo '{{"name": "@strudel/repl", "version": "{REPL_VERSION}"}}' > node_modules/@strudel/repl/package.json
""")
        done = box.run("toolchain/setup.sh")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(lines(done), [
            f"     npm ci (@strudel/repl {REPL_VERSION})",
            f"ok   strudel {REPL_VERSION} · AGPL-3.0-or-later, from npm, unmodified",
        ])
        # From the package dir, whatever the caller's cwd, and from the lockfile.
        self.assertEqual((box.dir / "npm.calls").read_text(), f"{box.root} ci --silent --no-audit --no-fund\n")

    def test_npm_ci_that_leaves_no_bundle(self) -> None:
        box = self.sandbox("node", "python3")
        self.npm(box, "exit 0\n")
        done = box.run("toolchain/setup.sh")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(lines(done)[-1], "miss the Strudel REPL bundle after npm ci")

    def test_a_failing_npm_ci_stops_setup(self) -> None:
        box = self.sandbox("node", "python3")
        self.npm(box, "echo 'npm ERR! network' >&2; exit 1\n")
        done = box.run("toolchain/setup.sh")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(lines(done), [f"     npm ci (@strudel/repl {REPL_VERSION})"])


class Doctor(unittest.TestCase):
    def test_a_ready_machine(self) -> None:
        box = Sandbox(self, ("node", "python3"))
        box.link("toolchain/doctor.sh")
        repl = box.root / "node_modules" / "@strudel" / "repl"
        (repl / "dist").mkdir(parents=True)
        (repl / "dist" / "index.js").write_text("export {}\n")
        (repl / "package.json").write_text('{"name": "@strudel/repl", "version": "9.9.9"}\n')
        done = box.run("toolchain/doctor.sh")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        out = lines(done)
        self.assertEqual(out[0], "ok   strudel 9.9.9 (the pane's REPL)")
        self.assertRegex(out[1], r"^ok   node v\d+\.\d+\.\d+ \(the pane server and the syntax check\)$")
        self.assertRegex(out[2], r"^ok   Python 3\.\d+\.\d+ \(the verdict\)$")
        self.assertTrue(out[3].startswith("note the pane needs a click to start audio"))
        self.assertEqual(len(out), 4)

    def test_an_empty_machine(self) -> None:
        box = Sandbox(self)
        box.link("toolchain/doctor.sh")
        done = box.run("toolchain/doctor.sh")
        self.assertEqual(done.returncode, 1)
        out = lines(done)
        self.assertEqual(out[:3], ["miss node_modules — run toolchain/setup.sh", "miss node >= 18", "miss python3"])
        self.assertTrue(out[3].startswith("note "))


class InitWorkspace(unittest.TestCase):
    def sandbox(self, *tools: str) -> tuple[Sandbox, Path]:
        box = Sandbox(self, tools)
        box.link("toolchain/init-workspace.sh")
        box.link("toolchain/verdict.py")
        ws = box.dir / "ws"
        ws.mkdir()
        shutil.copy(PKG / "template" / "track.strudel", ws / "track.strudel")
        return box, ws

    def test_it_needs_the_install_dir(self) -> None:
        box, ws = self.sandbox("python3")
        done = box.run("toolchain/init-workspace.sh", cwd=ws)
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", done.stderr)
        self.assertFalse((ws / ".harness").exists())

    def test_it_seeds_the_verdict_for_the_starter_track(self) -> None:
        box, ws = self.sandbox("python3", "node")
        done = box.run("toolchain/init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.root))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout, "")
        verdict = json.loads((ws / ".harness" / "verdict.json").read_text())
        self.assertTrue(verdict["ready"])
        self.assertEqual(verdict["artifact"], "track.strudel")

    def test_a_verdict_that_cannot_run_does_not_fail_the_init(self) -> None:
        box, ws = self.sandbox()                                    # no python3 on PATH
        done = box.run("toolchain/init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.root))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue((ws / ".harness").is_dir())
        self.assertFalse((ws / ".harness" / "verdict.json").exists())


class ViewerLauncher(unittest.TestCase):
    def sandbox(self) -> Sandbox:
        box = Sandbox(self, ("pwd",))
        box.link("viewer.sh")
        box.stub("node", 'echo "node $* in $PWD port=$HARNESS_VIEWER_PORT ws=$HARNESS_WORKSPACE"\n')
        return box

    def test_it_needs_a_port_and_a_workspace(self) -> None:
        box = self.sandbox()
        no_port = box.run("viewer.sh", HARNESS_WORKSPACE=str(box.dir))
        self.assertNotEqual(no_port.returncode, 0)
        self.assertIn("HARNESS_VIEWER_PORT", no_port.stderr)
        no_ws = box.run("viewer.sh", HARNESS_VIEWER_PORT="4100")
        self.assertNotEqual(no_ws.returncode, 0)
        self.assertIn("HARNESS_WORKSPACE", no_ws.stderr)
        self.assertEqual(no_port.stdout + no_ws.stdout, "")

    def test_it_runs_the_viewer_beside_it(self) -> None:
        box = self.sandbox()
        done = box.run("viewer.sh", HARNESS_VIEWER_PORT="4100", HARNESS_WORKSPACE="/Users/example/track")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout, f"node {box.root}/viewer.mjs in {box.dir} port=4100 ws=/Users/example/track\n")


if __name__ == "__main__":
    unittest.main()
