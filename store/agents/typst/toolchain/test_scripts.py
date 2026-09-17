"""setup.sh, doctor.sh and init-workspace.sh, run for real against a scratch install whose PATH holds
only stub commands (and the few coreutils the scripts use), so every ok / miss line is reached
without a network or a Typst on the machine:

    python3 -m unittest toolchain/test_scripts.py
"""
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent
# A bash line tracer (BASH_ENV sourcing a DEBUG trap that appends to SHCOV_OUT) is passed through when set.
TRACER = {k: os.environ[k] for k in ("BASH_ENV", "SHCOV_OUT") if k in os.environ}
BASH = "/bin/bash"
COREUTILS = ("dirname", "cat", "mkdir", "cp", "rm", "chmod", "grep")
VERSION = (PACKAGE / "TYPST_VERSION").read_text().strip()


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
        shutil.copy(PACKAGE / "TYPST_VERSION", self.install / "TYPST_VERSION")
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

    def run(self, script: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run([BASH, str(self.install / "toolchain" / script)], cwd=cwd or self.install,
                              env={"PATH": str(self.bin), "CALLS": str(self.calls), **TRACER, **env},
                              capture_output=True, text=True, timeout=60)

    def logged(self) -> list[str]:
        return self.calls.read_text().splitlines()


class Doctor(unittest.TestCase):
    def test_ready(self):
        box = Sandbox(self)
        box.stub("typst", f'echo "typst {VERSION[1:]} (abc)"', where=box.install / "bin")
        box.stub("python3", 'echo "Python 3.12.1"')
        r = box.run("doctor.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [f"ok   typst {VERSION[1:]} (abc)", "ok   Python 3.12.1 for the verdict"])

    def test_no_typst_is_a_miss_and_stops(self):
        box = Sandbox(self)
        box.stub("python3", 'echo "Python 3.12.1"')
        r = box.run("doctor.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines(), ["miss bin/typst — run toolchain/setup.sh"])

    def test_no_python_is_a_miss(self):
        box = Sandbox(self)
        box.stub("typst", 'echo "typst 0.15.1"', where=box.install / "bin")
        r = box.run("doctor.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[-1], "miss python3 for the verdict")


class Setup(unittest.TestCase):
    def sandbox(self, system="Darwin", machine="arm64") -> Sandbox:
        box = Sandbox(self)
        box.stub("uname", f'[ "$1" = -s ] && echo {system} || echo {machine}')
        # curl writes the archive it was asked for; tar unpacks a typst that knows its version.
        box.stub("curl", 'while [ $# -gt 1 ]; do [ "$1" = -o ] && out="$2"; shift; done; echo archive > "$out"')
        box.stub("tar", f'dir="$4/$(basename "$2" .tar.xz)"; mkdir -p "$dir"; printf \'#!/bin/bash\\necho "typst {VERSION[1:]} (fetched)"\\n\' > "$dir/typst"')
        (box.bin / "basename").symlink_to("/usr/bin/basename")
        return box

    def test_downloads_the_release_for_each_machine(self):
        for system, machine, asset in (("Darwin", "arm64", "typst-aarch64-apple-darwin.tar.xz"),
                                       ("Darwin", "x86_64", "typst-x86_64-apple-darwin.tar.xz"),
                                       ("Linux", "x86_64", "typst-x86_64-unknown-linux-musl.tar.xz"),
                                       ("Linux", "aarch64", "typst-aarch64-unknown-linux-musl.tar.xz")):
            with self.subTest(machine=f"{system}-{machine}"):
                box = self.sandbox(system, machine)
                r = box.run("setup.sh")
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(r.stdout.splitlines(), [f"     downloading typst {VERSION} ({asset})", f"ok   typst {VERSION[1:]} (fetched)"])
                self.assertIn(f"curl -fsSL -o tmp/{asset} https://github.com/typst/typst/releases/download/{VERSION}/{asset}", box.logged())
                self.assertTrue(os.access(box.install / "bin" / "typst", os.X_OK))
                self.assertFalse((box.install / "tmp").exists(), "the download is cleaned up")

    def test_an_unknown_machine_is_a_miss(self):
        r = self.sandbox("FreeBSD", "riscv64").run("setup.sh")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.strip(), "miss no Typst release for FreeBSD-riscv64")

    def test_the_pinned_version_already_here_is_kept(self):
        box = self.sandbox()
        box.stub("typst", f'echo "typst {VERSION[1:]} (old install)"', where=box.install / "bin")
        r = box.run("setup.sh")
        self.assertEqual((r.returncode, r.stdout.strip()), (0, f"ok   typst {VERSION} already here"))
        self.assertFalse(any(c.startswith("curl") for c in box.logged()))

    def test_another_version_is_replaced(self):
        box = self.sandbox()
        box.stub("typst", 'echo "typst 0.1.0"', where=box.install / "bin")
        r = box.run("setup.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines()[-1], f"ok   typst {VERSION[1:]} (fetched)")

    def test_a_failed_download_fails_setup(self):
        box = self.sandbox()
        box.stub("curl", "exit 22")
        r = box.run("setup.sh")
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((box.install / "bin" / "typst").exists())


class InitWorkspace(unittest.TestCase):
    def test_compiles_the_template_and_seeds_the_verdict(self):
        box = Sandbox(self)
        ws = box.root / "ws"
        ws.mkdir()
        box.stub("typst", "exit 1", where=box.install / "bin")      # a failing compile does not stop init
        box.stub("python3", "exit 1")
        r = box.run("init-workspace.sh", cwd=ws, HARNESS_DSH_DIR=str(box.install))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((ws / ".harness").is_dir() and (ws / "out").is_dir())
        self.assertEqual(box.logged(), ["typst compile main.typ out/main.pdf", f"python3 {box.install}/toolchain/verdict.py"])

    def test_needs_the_install_dir(self):
        box = Sandbox(self)
        r = box.run("init-workspace.sh", cwd=box.root)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", r.stderr)


if __name__ == "__main__":
    unittest.main()
