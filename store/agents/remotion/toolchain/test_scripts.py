"""setup.sh, doctor.sh, init-workspace.sh and the two wrappers ($REMOTION, viewer.sh), run for real
against a scratch install whose PATH holds only stub commands (node, npm, python3, git) and the few
coreutils the scripts use, so every ok / warn / miss line is reached without a network, npm or
Remotion on the machine:

    python3 -m unittest toolchain/test_scripts.py
"""
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent
# A bash line tracer (BASH_ENV sourcing a DEBUG trap that appends to SHCOV_OUT) is passed through when set.
TRACER = {k: os.environ[k] for k in ("BASH_ENV", "SHCOV_OUT") if k in os.environ}
BASH = "/bin/bash"
COREUTILS = ("dirname", "cat", "mkdir", "rm", "ls", "tr", "ln")
VERSIONS = dict(line.split("=", 1) for line in (PACKAGE / "VERSIONS").read_text().split())
COMMIT = VERSIONS["SKILLS_COMMIT"]

# node as the scripts use it: -e is the version check (NODE_OK), -p reads a package version, -v.
NODE = """case "$1" in
  -e) exit "${NODE_OK:-0}" ;;
  -p) case "$2" in *remotion/package.json*) echo 4.0.525 ;; *react/package.json*) echo 19.3.0 ;; esac ;;
  -v) echo v22.1.0 ;;
  *) exit "${NODE_CODE:-0}" ;;
esac"""
# git as setup.sh uses it: the checkout lays out the skills (unless GIT_EMPTY), a fetch can fail.
GIT = """[ "$1" = fetch ] && exit "${GIT_FETCH:-0}"
if [ "$1" = checkout ] && [ -z "$GIT_EMPTY" ]; then
  mkdir -p skills/remotion-best-practices skills/remotion-captions
  echo skill > skills/remotion-best-practices/SKILL.md
fi
exit 0"""


class Sandbox:
    """An install dir linking the package's scripts, a bin/ of stubs as the whole PATH, and a log of
    every stub call."""

    def __init__(self, test: unittest.TestCase):
        tmp = tempfile.TemporaryDirectory()
        test.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.install = self.root / "install"
        (self.install / "toolchain").mkdir(parents=True)
        # Linked, not copied, so a line tracer maps back to the source. Never chmod or write these.
        for name in ("setup.sh", "doctor.sh", "init-workspace.sh", "remotion"):
            (self.install / "toolchain" / name).symlink_to(PACKAGE / "toolchain" / name)
        (self.install / "viewer.sh").symlink_to(PACKAGE / "viewer.sh")
        shutil.copy(PACKAGE / "VERSIONS", self.install / "VERSIONS")
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
        path.unlink(missing_ok=True)  # never write through a link to a real binary
        path.write_text(f'#!/bin/bash\necho "{name} $*" >> "$CALLS"\n{body}\n')
        path.chmod(0o755)
        return path

    def tools(self, *names: str) -> "Sandbox":
        bodies = {"node": NODE, "git": GIT, "npm": 'exit "${NPM_CODE:-0}"', "python3": '[ "$1" = --version ] && echo "Python 3.12.1"; exit "${PY_CODE:-0}"'}
        for name in names:
            self.stub(name, bodies[name])
        return self

    def skills(self, commit: str | None = COMMIT) -> None:
        skill = self.install / "upstream" / "skills" / "remotion-best-practices" / "SKILL.md"
        skill.parent.mkdir(parents=True, exist_ok=True)
        skill.write_text("skill")
        if commit is not None:
            (self.install / "upstream" / ".harness-commit").write_text(commit + "\n")

    def run(self, script: str, *args: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run([BASH, str(self.install / script), *args], cwd=cwd or self.install,
                              env={"PATH": str(self.bin), "CALLS": str(self.calls), **TRACER, **env},
                              capture_output=True, text=True, timeout=60)

    def logged(self) -> list[str]:
        return self.calls.read_text().splitlines()


class Setup(unittest.TestCase):
    def sandbox(self) -> Sandbox:
        box = Sandbox(self).tools("node", "npm", "python3", "git")
        box.stub("remotion", 'exit "${BROWSER_CODE:-0}"', where=box.install / "node_modules" / ".bin")
        return box

    def test_a_first_install(self):
        box = self.sandbox()
        r = box.run("toolchain/setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            "     npm ci (remotion 4.0.525, a few minutes the first time)",
            "ok   remotion 4.0.525 · react 19.3.0",
            "     remotion browser ensure (the headless Chrome renders use)",
            "ok   headless browser",
            f"     fetching remotion-dev/skills @ {COMMIT}",
            "ok   skills: remotion-best-practices remotion-captions ",
        ])
        self.assertIn("npm ci --silent --no-audit --no-fund", box.logged())
        self.assertIn("remotion browser ensure", box.logged())
        git = [c for c in box.logged() if c.startswith("git ")]
        self.assertEqual(git, ["git init -q", "git remote add origin https://github.com/remotion-dev/skills.git",
                               f"git fetch -q --depth 1 origin {COMMIT}", "git checkout -q FETCH_HEAD"])
        self.assertEqual((box.install / "upstream" / ".harness-commit").read_text(), COMMIT + "\n")

    def test_skills_at_the_pinned_commit_are_kept_and_no_browser_is_a_warning(self):
        box = self.sandbox()
        box.skills()
        r = box.run("toolchain/setup.sh", BROWSER_CODE="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("warn no headless browser yet — renders will fetch it on first use", r.stdout.splitlines())
        self.assertEqual(r.stdout.splitlines()[-1], "ok   skills: remotion-best-practices ")
        self.assertFalse(any(c.startswith("git ") for c in box.logged()))

    def test_skills_at_another_commit_are_fetched_again(self):
        box = self.sandbox()
        box.skills("0000000")
        (box.install / "upstream" / "stale.txt").write_text("old")
        r = box.run("toolchain/setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"     fetching remotion-dev/skills @ {COMMIT}", r.stdout.splitlines())
        self.assertFalse((box.install / "upstream" / "stale.txt").exists())

    def test_a_fetch_without_the_skill_is_a_miss(self):
        r = self.sandbox().run("toolchain/setup.sh", GIT_EMPTY="1")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[-1], "miss upstream/skills/remotion-best-practices/SKILL.md")

    def test_failures_stop_setup(self):
        for env in ({"NPM_CODE": "1"}, {"GIT_FETCH": "128"}):
            with self.subTest(**env):
                r = self.sandbox().run("toolchain/setup.sh", **env)
                self.assertNotEqual(r.returncode, 0)
                self.assertFalse(r.stdout.splitlines()[-1].startswith("ok   skills"))

    def test_missing_tools_are_misses(self):
        cases = (((), {}, "miss node >= 18 on PATH"),
                 (("node",), {"NODE_OK": "1"}, "miss node >= 18 on PATH"),
                 (("node",), {}, "miss npm on PATH"),
                 (("node", "npm"), {}, "miss python3 (the verdict)"))
        for tools, env, line in cases:
            with self.subTest(line=line, tools=tools):
                box = Sandbox(self).tools(*tools)
                r = box.run("toolchain/setup.sh", **env)
                self.assertEqual((r.returncode, r.stdout.strip()), (1, line))


class Doctor(unittest.TestCase):
    def test_ready(self):
        box = Sandbox(self).tools("node", "python3")
        box.stub("remotion", where=box.install / "node_modules" / ".bin")
        box.skills()
        r = box.run("toolchain/doctor.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            "ok   remotion 4.0.525",
            f"ok   skills @ {COMMIT}",
            "ok   $REMOTION (render progress for the pane) · node v22.1.0",
            "ok   Python 3.12.1",
        ])

    def test_nothing_installed(self):
        box = Sandbox(self).tools("node")
        r = box.run("toolchain/doctor.sh", NODE_OK="1")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines(), [
            "miss node_modules — run toolchain/setup.sh",
            "miss upstream skills — run toolchain/setup.sh",
            "miss node >= 18 or an executable toolchain/remotion",
            "miss python3",
        ])

    def test_no_executable_wrapper_and_no_commit_file(self):
        box = Sandbox(self).tools("node", "python3")
        box.stub("remotion", where=box.install / "node_modules" / ".bin")
        box.skills(commit=None)
        (box.install / "toolchain" / "remotion").unlink()
        r = box.run("toolchain/doctor.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[1:3], ["ok   skills @ ", "miss node >= 18 or an executable toolchain/remotion"])


class InitWorkspace(unittest.TestCase):
    def test_links_the_shared_node_modules_and_seeds_the_verdict(self):
        box = Sandbox(self).tools("python3")
        ws = box.root / "ws"
        ws.mkdir()
        r = box.run("toolchain/init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.install), PY_CODE="1")  # a failing verdict does not stop init
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(all((ws / d).is_dir() for d in (".harness", "out", "public")))
        self.assertEqual(os.readlink(ws / "node_modules"), f"{box.install}/node_modules")
        self.assertEqual(box.logged(), [f"python3 {box.install}/toolchain/verdict.py"])

    def test_a_node_modules_already_there_is_kept(self):
        box = Sandbox(self).tools("python3")
        ws = box.root / "ws"
        (ws / "node_modules").mkdir(parents=True)
        r = box.run("toolchain/init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.install))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((ws / "node_modules").is_symlink())

    def test_needs_the_install_dir(self):
        box = Sandbox(self)
        r = box.run("toolchain/init-workspace.sh", cwd=box.root)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", r.stderr)


class Wrappers(unittest.TestCase):
    def test_remotion_is_node_on_remotion_mjs_with_the_same_arguments_and_exit_code(self):
        box = Sandbox(self).tools("node")
        r = box.run("toolchain/remotion", "render", "Main", "out/main.mp4", NODE_CODE="7")
        self.assertEqual(r.returncode, 7)
        self.assertEqual(box.logged(), [f"node {box.install}/toolchain/remotion.mjs render Main out/main.mp4"])

    def test_viewer_sh_runs_the_pane_server(self):
        box = Sandbox(self).tools("node")
        r = box.run("viewer.sh", HARNESS_VIEWER_PORT="4321", HARNESS_WORKSPACE=str(box.root))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(box.logged(), [f"node {box.install}/viewer.mjs"])

    def test_viewer_sh_needs_its_port_and_workspace(self):
        box = Sandbox(self).tools("node")
        for env, missing in (({"HARNESS_WORKSPACE": "/tmp"}, "HARNESS_VIEWER_PORT"), ({"HARNESS_VIEWER_PORT": "1"}, "HARNESS_WORKSPACE")):
            with self.subTest(missing=missing):
                r = box.run("viewer.sh", **env)
                self.assertNotEqual(r.returncode, 0)
                self.assertIn(missing, r.stderr)
        self.assertEqual(box.logged(), [])


if __name__ == "__main__":
    unittest.main()
