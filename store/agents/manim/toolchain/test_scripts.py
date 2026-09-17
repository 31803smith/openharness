"""setup.sh, doctor.sh and init-workspace.sh, run for real against a scratch install whose PATH holds
only stub commands (and the few coreutils the scripts use), so every ok / miss / warn line is reached
without a network, a Python venv or Manim on the machine:

    python3 -m unittest toolchain/test_scripts.py
"""
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent
# A bash line tracer (BASH_ENV sourcing a DEBUG trap that appends to SHCOV_OUT) is passed through when set.
TRACER = {k: os.environ[k] for k in ("BASH_ENV", "SHCOV_OUT") if k in os.environ}
BASH = "/bin/bash"
COREUTILS = ("dirname", "cat", "mkdir", "cp", "head", "cut")
VERSION = (PACKAGE / "MANIM_VERSION").read_text().strip()


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
        shutil.copy(PACKAGE / "MANIM_VERSION", self.install / "MANIM_VERSION")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.templates = self.root / "templates"
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

    def run(self, script: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run([BASH, str(self.install / "toolchain" / script)], cwd=cwd or self.install,
                              env={"PATH": str(self.bin), "CALLS": str(self.calls), **TRACER, **env},
                              capture_output=True, text=True, timeout=60)

    def logged(self) -> list[str]:
        return self.calls.read_text().splitlines()

    # The machine's pieces, as the scripts ask about them.
    def uname(self, system: str) -> None:
        self.stub("uname", f"echo {system}")

    def pkg_config(self, cairo: bool = True) -> None:
        self.stub("pkg-config", f'[ "$1" = --modversion ] && {{ echo 1.18.4; exit 0; }}; exit {0 if cairo else 1}')

    def ffmpeg(self) -> None:
        self.stub("ffmpeg", 'echo "ffmpeg version 7.1.1 Copyright (c) the FFmpeg developers"')

    def venv(self, where: Path) -> None:
        """A .venv whose python runs pip (failing when $PIP_EXIT says so) and whose manim has a version."""
        self.stub("python", '[ "$*" = "-m pip install --quiet --upgrade pip" ] && exit 1\n[ "$2" = pip ] && exit "${PIP_EXIT:-0}"\nexit 0', where=where / ".venv" / "bin")
        self.stub("manim", f'echo "Manim Community v{VERSION}"', where=where / ".venv" / "bin")


class Doctor(unittest.TestCase):
    def test_everything_there_on_a_mac(self):
        box = Sandbox(self)
        box.uname("Darwin"); box.pkg_config(); box.ffmpeg(); box.stub("latex")
        box.venv(box.install)
        r = box.run("doctor.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [f"ok   manim {VERSION}", "ok   ffmpeg", "ok   latex (Tex/MathTex available)"])

    def test_nothing_there_on_linux_misses_and_warns(self):
        box = Sandbox(self)
        box.uname("Linux")                                   # cairo is not checked off a Mac
        r = box.run("doctor.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines(), [
            "miss .venv/bin/manim — run toolchain/setup.sh",
            "miss ffmpeg on PATH (brew install ffmpeg)",
            "warn latex not on PATH — Tex/MathTex scenes need it (brew install --cask mactex-no-gui); Text() works without",
        ])

    def test_a_mac_without_pkg_config_or_without_cairo(self):
        for label, prepare in (("no pkg-config", lambda box: None), ("no cairo", lambda box: box.pkg_config(cairo=False))):
            with self.subTest(label):
                box = Sandbox(self)
                box.uname("Darwin"); box.ffmpeg(); box.venv(box.install); prepare(box)
                r = box.run("doctor.sh")
                self.assertEqual(r.returncode, 1)
                self.assertIn("miss cairo and pkg-config (brew install cairo pkgconf)", r.stdout.splitlines())

    def test_a_missing_ffmpeg_alone_fails_the_doctor(self):
        box = Sandbox(self)
        box.uname("Linux"); box.venv(box.install); box.stub("latex")
        r = box.run("doctor.sh")
        self.assertEqual((r.returncode, r.stdout.splitlines()[1]), (1, "miss ffmpeg on PATH (brew install ffmpeg)"))


class Setup(unittest.TestCase):
    def sandbox(self, system: str = "Linux", pythons: dict[str, bool] | None = None) -> Sandbox:
        """`pythons`: which interpreters exist and whether each is new enough."""
        box = Sandbox(self)
        box.uname(system)
        box.venv(box.templates)
        for name, new_enough in (pythons if pythons is not None else {"python3.12": True}).items():
            box.stub(name, f'case "$1" in\n  -c) exit {0 if new_enough else 1} ;;\n  --version) echo "Python 3.x ({name})" ;;\n'
                           f'  -m) mkdir -p .venv && cp -R "{box.templates}/.venv/bin" .venv/bin ;;\nesac')
        return box

    def test_installs_manim_into_a_venv(self):
        box = self.sandbox()
        box.ffmpeg()
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            "ok   Python 3.x (python3.12)",
            f"     installing manim {VERSION} (a couple of minutes the first time)",
            f"ok   manim Manim Community v{VERSION}",
            "ok   ffmpeg 7.1.1",
        ])
        self.assertIn("python3.12 -m venv .venv", box.logged())
        self.assertIn(f"python -m pip install --quiet manim=={VERSION}", box.logged())

    def test_the_first_new_enough_python_wins_and_an_existing_venv_is_kept(self):
        box = self.sandbox(pythons={"python3.11": False, "python3.13": True, "python3": True})
        box.venv(box.install)
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines()[0], "ok   Python 3.x (python3.13)")
        self.assertFalse(any("-m venv" in call for call in box.logged()), "the venv was already there")
        self.assertEqual(r.stdout.splitlines()[-1], "warn ffmpeg not on PATH — renders need it: brew install ffmpeg")

    def test_no_python_new_enough_is_a_miss(self):
        r = self.sandbox(pythons={"python3": False}).run("setup.sh")
        self.assertEqual((r.returncode, r.stdout.strip()), (1, "miss python 3.11+ (brew install python@3.12)"))

    def test_a_mac_needs_cairo_to_build_pycairo(self):
        box = self.sandbox("Darwin")
        box.ffmpeg()
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[-1], "miss pycairo builds from source and needs: pkgconf cairo — run: brew install pkgconf cairo")
        box = self.sandbox("Darwin")
        box.pkg_config(cairo=False)
        self.assertEqual(box.run("setup.sh").stdout.splitlines()[-1], "miss pycairo builds from source and needs: cairo — run: brew install cairo")

    def test_a_mac_with_cairo(self):
        box = self.sandbox("Darwin")
        box.pkg_config(); box.ffmpeg()
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines()[1], "ok   cairo 1.18.4 (manimpango ships its own pango)")

    def test_a_failed_install_fails_setup(self):
        box = self.sandbox()
        r = box.run("setup.sh", PIP_EXIT="1")
        self.assertEqual(r.returncode, 1)
        self.assertFalse(any(line.startswith("ok   manim") for line in r.stdout.splitlines()))


class InitWorkspace(unittest.TestCase):
    def init(self, render_exit: int, verdict_exit: int):
        box = Sandbox(self)
        ws = box.root / "ws"
        ws.mkdir()
        box.stub("python", f'case "$1" in\n  */render.py) echo "HARNESS_WORKSPACE=$HARNESS_WORKSPACE" >> "$CALLS"; exit {render_exit} ;;\n  *) exit {verdict_exit} ;;\nesac',
                 where=box.install / ".venv" / "bin")
        r = box.run("init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.install))
        return box, ws, r

    def test_renders_the_template_scene_for_the_pane(self):
        box, ws, r = self.init(0, 0)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((ws / ".harness").is_dir() and (ws / "out").is_dir())
        self.assertEqual(box.logged(), [f"python {box.install}/toolchain/render.py -ql --disable_caching scenes/intro.py Intro",
                                        f"HARNESS_WORKSPACE={ws.resolve()}"])

    def test_a_failed_render_still_seeds_the_verdict_and_init_never_fails(self):
        for verdict_exit in (0, 1):
            with self.subTest(verdict_exit=verdict_exit):
                box, _, r = self.init(1, verdict_exit)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(box.logged()[-1], f"python {box.install}/toolchain/verdict.py")

    def test_needs_the_install_dir(self):
        box = Sandbox(self)
        r = box.run("init-workspace.sh", cwd=box.root)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", r.stderr)


if __name__ == "__main__":
    unittest.main()
