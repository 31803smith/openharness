"""The shell half of the toolchain — flow.sh, setup.sh, doctor.sh, init-workspace.sh, viewer.sh — on
stub tools: `python3 -m unittest toolchain/test_scripts.py`.

Each test builds a throwaway install (the real scripts symlinked in, file by file), a workspace, a
directory of stub tools that log how they were called, and a PATH made of those stubs plus links to
the few system tools the scripts use, so a tool is missing exactly when a test leaves it out. The
scripts fall back to Homebrew's bin when yosys is not on PATH; a test that needs a tool to stay
missing after that hides it with a `command -v` wrapper exported into bash. One test at the end runs
the real flow on the starter design, when yosys, nextpnr, icestorm and icarus are installed.
"""
import atexit
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

PKG = Path(__file__).resolve().parent.parent
SYSTEM = ["bash", "basename", "cat", "chmod", "date", "dirname", "head", "ln", "mkdir", "perl", "rm", "sed", "tail"]
# `command -v <tool>` fails for every tool named in $STUB_HIDE, wherever it is installed.
HIDE = '() { if [ "$1" = -v ]; then case " $STUB_HIDE " in *" $2 "*) return 1;; esac; fi; builtin command "$@"; }'
SCRUB = ("HARNESS_WORKSPACE", "HARNESS_DSH_DIR", "HARNESS_VIEWER_PORT", "YOSYS_TOP", "YOSYS_DEVICE",
         "YOSYS_PACKAGE", "YOSYS_TOOLCHAIN", "STUB_FAIL", "STUB_HIDE")

# What each stub does besides logging its argv. $STUB_FAIL names the stubs that fail instead.
STUBS = {
    "iverilog": 'case "$1" in -V) echo "Icarus Verilog version 13.0 (stable)"; exit 0;; esac\n'
                ': > out/sim.vvp\n',
    "vvp": 'echo "  ok   green LED toggled"\necho "PASS  blink: 1 check"\n'
           '[ -n "$STUB_NO_VCD" ] || printf \'$timescale 1ps $end\\n$var wire 1 ! clk $end\\n'
           '$enddefinitions $end\\n#0\\n0!\\n#5\\n1!\\n\' > out/sim.vcd\n',
    "yosys": 'case "$1" in -V) echo "Yosys 0.99 (stub)"; exit 0;; esac\n'
             'case "$*" in\n'
             '  *synth_ice40*) printf \'=== blink ===\\n\\n       77 cells\\n       32   SB_LUT4\\n\'; echo "{}" > out/blink.json;;\n'
             '  *prep*) echo "{}" > out/blink_schematic.json;;\n'
             'esac\n',
    "netlistsvg": 'echo "<svg/>" > "$3"\n',
    "nextpnr-ice40": 'case "$1" in --version) echo "nextpnr-ice40 -- Next Generation Place and Route (stub)"; exit 0;; esac\n'
                     ': > out/blink.asc\n'
                     'echo \'{"utilization": {"ICESTORM_LC": {"used": 36, "available": 5280}}, '
                     '"fmax": {"clk": {"achieved": 60.0, "constraint": 12.0}}}\' > out/blink_pnr.json\n'
                     'echo "{}" > out/blink_routed.json\n',
    "icepack": 'printf "bits" > out/blink.bin\n',
    "iceprog": "",
    "brew": "",
    "node": 'case "$1" in -v) echo v22.0.0;; -p) echo 1.0.2;; esac\n',
    "npm": 'mkdir -p node_modules/.bin && printf "#!/bin/sh\\n" > node_modules/.bin/netlistsvg && chmod +x node_modules/.bin/netlistsvg\n',
}


_STUB_DIR = None


def stub_file(name, body):
    """One file per distinct stub for the whole run, hard-linked into each sandbox: macOS checks every
    new executable on its first run (most of a second each), and a link is not new."""
    global _STUB_DIR
    if _STUB_DIR is None:
        _STUB_DIR = Path(tempfile.mkdtemp(prefix="yosys-stubs-"))
        atexit.register(shutil.rmtree, _STUB_DIR, True)
    path = _STUB_DIR / hashlib.sha1(f"{name}\0{body}".encode()).hexdigest()[:16] / name
    if not path.exists():
        path.parent.mkdir()
        path.write_text(
            "#!/bin/sh\n"
            f'echo "{name} $*" >> "$STUB_CALLS"\n'
            f'case " $STUB_FAIL " in *" {name} "*) echo "{name}: stub failure"; exit 1;; esac\n' + body)
        path.chmod(0o755)
    return path


class Sandbox:
    """An install, a workspace, stub tools and a PATH, all under one temp dir."""

    def __init__(self, test: unittest.TestCase, stubs=(), system=SYSTEM, python=True):
        self.root = Path(tempfile.mkdtemp(prefix="yosys-sh-"))
        test.addCleanup(shutil.rmtree, self.root, True)
        self.pkg = self.root / "install"
        self.ws = self.root / "ws"
        self.bin = self.root / "stubs"
        self.sys = self.root / "system"
        self.calls = self.root / "calls.log"
        for d in (self.pkg / "toolchain", self.ws, self.bin, self.sys):
            d.mkdir(parents=True)
        for name in ("flow.sh", "setup.sh", "doctor.sh", "init-workspace.sh", "verdict.py", "vcd2json.py"):
            (self.pkg / "toolchain" / name).symlink_to(PKG / "toolchain" / name)
        (self.pkg / "viewer.sh").symlink_to(PKG / "viewer.sh")
        for name in system:
            found = shutil.which(name, path="/usr/bin:/bin:/usr/sbin:/sbin")
            if found:
                (self.sys / name).symlink_to(found)
        if python:
            (self.sys / "python3").symlink_to(os.path.realpath(shutil.which("python3")))
        for name in stubs:
            self.stub(name)

    def stub(self, name, body=None, where=None):
        path = (where or self.bin) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.unlink(missing_ok=True)
        os.link(stub_file(name, STUBS.get(name, "") if body is None else body), path)
        return path

    def run(self, argv, cwd=None, hide=(), **env):
        full = {k: v for k, v in os.environ.items() if k not in SCRUB}
        full.update(PATH=f"{self.bin}:{self.sys}", STUB_CALLS=str(self.calls), STUB_BIN=str(self.bin), LC_ALL="C")
        if hide:
            full["BASH_FUNC_command%%"] = HIDE
            full["STUB_HIDE"] = " ".join(hide)
        full.update({k: str(v) for k, v in env.items()})
        return subprocess.run([str(a) for a in argv], cwd=cwd or self.ws, env=full,
                              capture_output=True, text=True, timeout=120)

    def called(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def design(self, rtl=True, tb=True, pcf=True, top="blink"):
        for sub, name, ok in (("rtl", f"{top}.v", rtl), ("tb", f"{top}_tb.v", tb), ("constraints", f"{top}.pcf", pcf)):
            if ok:
                (self.ws / sub).mkdir(exist_ok=True)
                (self.ws / sub / name).write_text("// stub\n")

    def log(self, step):
        return (self.ws / "out" / "logs" / f"{step}.log").read_text()

    def exit_of(self, step):
        f = self.ws / "out" / "logs" / f"{step}.exit"
        return f.read_text().strip() if f.exists() else None


ALL_FLOW = ("iverilog", "vvp", "yosys", "nextpnr-ice40", "icepack")


class Flow(unittest.TestCase):
    def flow(self, sb, *args, **env):
        return sb.run([sb.pkg / "toolchain" / "flow.sh", *args], **env)

    def with_netlistsvg(self, sb):
        sb.stub("netlistsvg", where=sb.pkg / "node_modules" / ".bin")

    def test_a_whole_run_on_stub_tools_is_ready(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design()
        self.with_netlistsvg(sb)
        r = self.flow(sb)  # the top comes from tb/blink_tb.v
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("flow: blink  (--up5k --package sg48, 1 RTL file(s))", r.stdout)
        self.assertIn("→ sim", r.stdout)
        self.assertIn("  PASS  blink: 1 check", r.stdout)  # a passing step shows its log's tail
        self.assertTrue(r.stdout.rstrip().splitlines()[-1].startswith("ready · blink · sim passes · 77 cells"), r.stdout)
        self.assertEqual([c.split()[0] for c in sb.called()],
                         ["iverilog", "vvp", "yosys", "yosys", "netlistsvg", "nextpnr-ice40", "icepack"])
        calls = sb.called()
        self.assertEqual(calls[0], "iverilog -g2012 -Wall -o out/sim.vvp rtl/blink.v tb/blink_tb.v")
        self.assertIn("read_verilog rtl/blink.v; synth_ice40 -top blink -json out/blink.json; stat", calls[2])
        self.assertIn("read_verilog rtl/blink.v; prep -top blink; write_json out/blink_schematic.json", calls[3])
        self.assertEqual(calls[4], "netlistsvg out/blink_schematic.json -o out/blink.svg")
        self.assertEqual(calls[5], "nextpnr-ice40 --up5k --package sg48 --json out/blink.json --pcf constraints/blink.pcf "
                                   "--asc out/blink.asc --report out/blink_pnr.json --write out/blink_routed.json")
        self.assertEqual(calls[6], "icepack out/blink.asc out/blink.bin")
        for step in ("sim", "waves", "synth", "schematic", "svg", "pnr", "pack"):
            self.assertEqual(sb.exit_of(step), "0", step)
            start, end = (sb.ws / "out" / "logs" / f"{step}.time").read_text().split()
            self.assertLessEqual(int(start), int(end))
            self.assertEqual((sb.ws / "out" / "logs" / f"{step}.start").read_text().strip(), start)
        run = json.loads((sb.ws / "out" / "logs" / "run.json").read_text())
        self.assertEqual((run["top"], run["device"], run["package"]), ("blink", "--up5k", "sg48"))
        self.assertGreaterEqual(run["finishedAt"], run["startedAt"])
        self.assertEqual((sb.ws / "out" / ".top").read_text(), "blink\n")
        self.assertEqual(json.loads((sb.ws / "out" / "waves.json").read_text())["signals"][0]["name"], "clk")
        verdict = json.loads((sb.ws / ".harness" / "verdict.json").read_text())
        self.assertTrue(verdict["ready"])

    def test_a_new_run_clears_the_last_runs_step_files(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design()
        logs = sb.ws / "out" / "logs"
        logs.mkdir(parents=True)
        for ext in ("log", "exit", "start", "time"):
            (logs / f"old.{ext}").write_text("1\n")
        self.flow(sb, "blink")
        self.assertEqual(sorted(p.name for p in logs.glob("old.*")), [])

    def test_the_argument_then_YOSYS_TOP_name_the_top_and_the_board_comes_from_the_environment(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design(top="uart")
        r = self.flow(sb, YOSYS_TOP="uart", YOSYS_DEVICE="--hx8k", YOSYS_PACKAGE="ct256")
        self.assertIn("flow: uart  (--hx8k --package ct256, 1 RTL file(s))", r.stdout)
        self.assertIn("nextpnr-ice40 --hx8k --package ct256 --json out/uart.json", "\n".join(sb.called()))
        run = json.loads((sb.ws / "out" / "logs" / "run.json").read_text())
        self.assertEqual((run["device"], run["package"]), ("--hx8k", "ct256"))
        r = self.flow(sb, "other", YOSYS_TOP="uart")
        self.assertIn("flow: other ", r.stdout)

    def test_no_top_module_is_an_error_before_anything_runs(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        (sb.ws / "tb").mkdir()
        r = self.flow(sb)
        self.assertEqual(r.returncode, 2)
        self.assertIn("flow.sh: no top module — pass one, or put tb/<top>_tb.v in the workspace", r.stderr)
        self.assertFalse((sb.ws / "out").exists())

    def test_a_missing_workspace_is_an_error(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        r = self.flow(sb, "blink", HARNESS_WORKSPACE=sb.root / "nowhere")
        self.assertEqual(r.returncode, 2)
        self.assertIn(f"no workspace at {sb.root / 'nowhere'}", r.stderr)

    def test_no_rtl_fails_sim_and_synth_and_skips_the_rest(self):
        # yosys is not on PATH either: flow.sh adds Homebrew's bin, and nothing here reaches a tool.
        sb = Sandbox(self)
        sb.design(rtl=False)
        r = self.flow(sb, HARNESS_WORKSPACE=sb.ws)
        self.assertEqual(r.returncode, 1)
        self.assertIn("flow: blink  (--up5k --package sg48, 0 RTL file(s))", r.stdout)
        self.assertIn("  failed (exit 1) — out/logs/sim.log\n  no rtl/*.v to simulate", r.stdout)
        self.assertEqual(sb.log("synth"), "no rtl/*.v to synthesise\n")
        self.assertEqual([sb.exit_of(s) for s in ("sim", "waves", "synth", "schematic", "svg", "pnr", "pack")],
                         ["1", None, "1", None, None, None, None])
        self.assertEqual(sb.called(), [])
        verdict = json.loads((sb.ws / ".harness" / "verdict.json").read_text())
        self.assertFalse(verdict["ready"])

    def test_no_testbench(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design(tb=False)
        self.flow(sb, "blink")
        self.assertEqual(sb.log("sim"), "no testbench at tb/blink_tb.v\n")
        self.assertEqual(sb.exit_of("sim"), "1")

    def test_a_compile_error_or_a_crashed_simulation_fails_sim_only(self):
        for tool in ("iverilog", "vvp"):
            with self.subTest(tool):
                sb = Sandbox(self, stubs=ALL_FLOW)
                sb.design()
                r = self.flow(sb, "blink", STUB_FAIL=tool)
                self.assertIn(f"{tool}: stub failure", sb.log("sim"))
                self.assertEqual((sb.exit_of("sim"), sb.exit_of("waves"), sb.exit_of("synth")), ("1", None, "0"))
                self.assertEqual(r.returncode, 1)

    def test_a_testbench_that_dumps_nothing_fails_even_over_an_old_vcd(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design()
        (sb.ws / "out").mkdir()
        (sb.ws / "out" / "sim.vcd").write_text("$enddefinitions $end\n")  # from an earlier run
        self.flow(sb, "blink", STUB_NO_VCD=1)
        self.assertEqual(sb.exit_of("sim"), "1")
        self.assertIn('no out/sim.vcd — the testbench needs $dumpfile("out/sim.vcd") and $dumpvars', sb.log("sim"))
        self.assertIsNone(sb.exit_of("waves"))

    def test_a_synthesis_error_skips_schematic_and_place_and_route(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design()
        r = self.flow(sb, "blink", STUB_FAIL="yosys")
        self.assertEqual([sb.exit_of(s) for s in ("synth", "schematic", "svg", "pnr", "pack")], ["1", None, None, None, None])
        self.assertIn("  failed (exit 1) — out/logs/synth.log\n  yosys: stub failure", r.stdout)

    def test_the_schematic_is_optional_for_the_bitstream(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design()
        self.flow(sb, "blink")  # no netlistsvg in the install
        self.assertEqual(sb.log("svg"), f"no netlistsvg at {sb.pkg}/node_modules/.bin/netlistsvg — run toolchain/setup.sh\n")
        self.assertEqual([sb.exit_of(s) for s in ("svg", "pnr", "pack")], ["1", "0", "0"])
        # HARNESS_DSH_DIR, when set, is where netlistsvg is looked for
        other = sb.root / "other-install"
        sb.stub("netlistsvg", where=other / "node_modules" / ".bin")
        self.flow(sb, "blink", HARNESS_DSH_DIR=other)
        self.assertEqual(sb.exit_of("svg"), "0")
        self.assertEqual((sb.ws / "out" / "blink.svg").read_text(), "<svg/>\n")
        # a schematic netlist that yosys could not write is not drawn, and does not stop the bitstream
        sb.stub("yosys", body='case "$*" in *prep*) exit 1;; *) printf "=== blink ===\\n" ;; esac\n')
        self.flow(sb, "blink", HARNESS_DSH_DIR=other)
        self.assertEqual([sb.exit_of(s) for s in ("synth", "schematic", "svg", "pnr", "pack")], ["0", "1", None, "0", "0"])

    def test_place_and_route_needs_nextpnr_and_the_pin_constraints(self):
        sb = Sandbox(self, stubs=("iverilog", "vvp", "yosys", "icepack"))
        sb.design()
        r = self.flow(sb, "blink")
        self.assertEqual(sb.log("pnr"), "nextpnr-ice40 is not installed — run toolchain/setup.sh\n")
        self.assertEqual((sb.exit_of("pnr"), sb.exit_of("pack")), ("127", None))
        self.assertIn("failed (exit 127) — out/logs/pnr.log", r.stdout)
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design(pcf=False)
        self.flow(sb, "blink")
        self.assertEqual(sb.log("pnr"), "no pin constraints at constraints/blink.pcf — every port needs a set_io line\n")
        self.assertEqual(sb.exit_of("pnr"), "1")

    def test_the_bitstream_needs_icepack(self):
        sb = Sandbox(self, stubs=("iverilog", "vvp", "yosys", "nextpnr-ice40"))
        sb.design()
        self.flow(sb, "blink")
        self.assertEqual(sb.log("pack"), "icepack is not installed — run toolchain/setup.sh\n")
        self.assertEqual(sb.exit_of("pack"), "127")

    def test_without_perl_the_clock_is_whole_seconds(self):
        sb = Sandbox(self, stubs=ALL_FLOW, system=[s for s in SYSTEM if s != "perl"])
        sb.design()
        before = int(time.time())
        self.flow(sb, "blink")
        start = (sb.ws / "out" / "logs" / "sim.start").read_text().strip()
        self.assertTrue(start.endswith("000"), start)
        self.assertGreaterEqual(int(start) // 1000, before)


class Setup(unittest.TestCase):
    TOOLS = ("yosys", "nextpnr-ice40", "icepack", "iverilog", "node", "npm")

    def setup_sh(self, sb, **kw):
        return sb.run([sb.pkg / "toolchain" / "setup.sh"], **kw)

    def test_everything_already_there(self):
        sb = Sandbox(self, stubs=self.TOOLS)
        r = self.setup_sh(sb)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            "ok   yosys, nextpnr-ice40, icestorm, icarus-verilog already on PATH",
            "     npm ci (netlistsvg 1.0.2, for the schematic)",
            "ok   Yosys 0.99 (stub)",
            "ok   nextpnr-ice40 · icepack · Icarus Verilog version 13.0 (stable)",
            "ok   netlistsvg 1.0.2 · node v22.0.0",
        ])
        self.assertIn("npm ci --silent --no-audit --no-fund", sb.called())
        self.assertTrue((sb.pkg / "node_modules" / ".bin" / "netlistsvg").exists())  # in the install, not the cwd

    def test_brew_installs_what_is_missing(self):
        sb = Sandbox(self, stubs=("yosys", "iverilog", "node", "npm"))
        sb.stub("brew", body=f'echo "HOMEBREW_NO_AUTO_UPDATE=$HOMEBREW_NO_AUTO_UPDATE" >> "$STUB_CALLS"\n'
                             f'ln "{stub_file("nextpnr-ice40", "")}" "{stub_file("icepack", "")}" "$STUB_BIN"\n')
        r = self.setup_sh(sb)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("     brew install nextpnr-ice40 icestorm  (the open-source FPGA flow; a few minutes the first time)", r.stdout)
        self.assertIn("brew install nextpnr-ice40 icestorm", sb.called())
        self.assertIn("HOMEBREW_NO_AUTO_UPDATE=1", sb.called())

    def test_a_formula_that_installs_without_its_binary(self):
        sb = Sandbox(self, stubs=("yosys", "nextpnr-ice40", "iverilog", "brew", "node", "npm"))
        r = self.setup_sh(sb)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[-1], "miss icepack even after installing icestorm")

    def test_no_brew_says_where_to_get_the_tools(self):
        sb = Sandbox(self, stubs=("yosys",))
        r = self.setup_sh(sb)
        self.assertEqual(r.returncode, 1)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[0], "miss nextpnr-ice40 icestorm icarus-verilog and no brew to install them with.")
        self.assertTrue(lines[1].startswith("     macOS:  /bin/bash -c "))
        self.assertEqual(lines[2], "     Linux:  apt install yosys nextpnr-ice40 fpga-icestorm iverilog")
        self.assertIn("oss-cad-suite", lines[3])

    def test_without_yosys_on_path_it_looks_in_homebrew_first(self):
        # Hidden everywhere, so the answer is the same on a machine that has them in /opt/homebrew.
        sb = Sandbox(self)
        r = self.setup_sh(sb, hide=("yosys", "nextpnr-ice40", "icepack", "iverilog", "brew"))
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[0],
                         "miss yosys nextpnr-ice40 icestorm icarus-verilog and no brew to install them with.")

    def test_node_npm_and_python_are_required(self):
        for missing, message in (("node", "miss node >= 18 on PATH (the viewer and netlistsvg)"),
                                 ("npm", "miss npm on PATH"),
                                 ("python3", "miss python3 (the VCD reader and the verdict)")):
            with self.subTest(missing):
                sb = Sandbox(self, stubs=[t for t in self.TOOLS if t != missing], python=missing != "python3")
                r = self.setup_sh(sb)
                self.assertEqual(r.returncode, 1)
                self.assertEqual(r.stdout.splitlines()[-1], message)
                self.assertNotIn("npm ci --silent --no-audit --no-fund", sb.called())

    def test_npm_ci_that_leaves_no_netlistsvg(self):
        sb = Sandbox(self, stubs=self.TOOLS)
        sb.stub("npm", body="")
        r = self.setup_sh(sb)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[-1], "miss node_modules/.bin/netlistsvg after npm ci")


class Doctor(unittest.TestCase):
    def doctor(self, sb, **kw):
        return sb.run([sb.pkg / "toolchain" / "doctor.sh"], **kw)

    def test_a_ready_machine(self):
        sb = Sandbox(self, stubs=("yosys", "nextpnr-ice40", "iverilog", "iceprog", "node"))
        prefix = sb.root / "icestorm"
        sb.stub("icepack", where=prefix / "bin")
        (sb.bin / "icepack").symlink_to(prefix / "bin" / "icepack")  # as Homebrew links it
        (prefix / "share" / "icestorm" / "chipdb").mkdir(parents=True)
        (prefix / "share" / "icestorm" / "chipdb" / "chipdb-5k.txt").write_text(".device 5k\n")
        sb.stub("netlistsvg", where=sb.pkg / "node_modules" / ".bin")
        r = self.doctor(sb)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(r.stdout.splitlines()[:8], [
            "ok   yosys, the synthesiser — Yosys 0.99 (stub)",
            "ok   nextpnr-ice40, place and route — nextpnr-ice40 -- Next Generation Place and Route (stub)",
            "ok   icepack, the bitstream packer (icestorm)",
            "ok   iverilog, the simulator — Icarus Verilog version 13.0 (stable)",
            "ok   iceprog, to flash a board over USB",
            "ok   netlistsvg 1.0.2, the schematic",
            "ok   node v22.0.0 for the viewer",
            "ok   IceStorm chipdb, for the pane's pin maps",
        ])
        self.assertTrue(r.stdout.splitlines()[8].startswith("ok   Python 3."))

    def test_a_bare_machine(self):
        sb = Sandbox(self)
        r = self.doctor(sb, hide=("yosys", "nextpnr-ice40", "icepack", "iverilog", "iceprog", "node", "python3"))
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines(), [
            "miss yosys — run toolchain/setup.sh",
            "miss nextpnr-ice40 — run toolchain/setup.sh",
            "miss icepack — run toolchain/setup.sh",
            "miss iverilog — run toolchain/setup.sh",
            "info iceprog not found — synthesis works, flashing a real board does not",
            "miss node_modules — run toolchain/setup.sh",
            "miss node for the viewer",
            "info IceStorm chipdb not found — the pane falls back to its built-in iCE40UP5K-SG48 pin table",
            "miss python3",
        ])

    def test_a_tool_that_is_installed_but_does_not_run_is_missing(self):
        sb = Sandbox(self, stubs=("nextpnr-ice40", "icepack"))
        sb.stub("yosys", body="")  # runs, prints nothing
        sb.stub("iverilog", body='echo "dyld[1]: Library not loaded: libexample.dylib"; exit 134\n')
        sb.stub("node", body='echo "node: Permission denied" >&2; exit 126\n')
        r = self.doctor(sb)
        self.assertEqual(r.returncode, 1)
        lines = r.stdout.splitlines()
        self.assertIn("miss yosys, the synthesiser", lines)
        self.assertIn("miss iverilog, the simulator", lines)
        self.assertIn("miss node for the viewer", lines)
        self.assertIn("info IceStorm chipdb not found — the pane falls back to its built-in iCE40UP5K-SG48 pin table", lines)


class InitWorkspace(unittest.TestCase):
    def test_needs_the_install_dir(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        r = sb.run([sb.pkg / "toolchain" / "init-workspace.sh"])
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_DSH_DIR", r.stderr)

    def test_runs_the_flow_on_the_starter_and_keeps_its_log(self):
        sb = Sandbox(self, stubs=ALL_FLOW)
        sb.design()
        sb.stub("netlistsvg", where=sb.pkg / "node_modules" / ".bin")
        r = sb.run([sb.pkg / "toolchain" / "init-workspace.sh"], HARNESS_DSH_DIR=sb.pkg)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(r.stdout, "")
        self.assertIn("flow: blink  (--up5k --package sg48, 1 RTL file(s))", (sb.ws / "out" / "logs-init.txt").read_text())
        self.assertEqual(sb.exit_of("pack"), "0")
        verdict = json.loads((sb.ws / ".harness" / "verdict.json").read_text())
        self.assertTrue(verdict["ready"], (verdict, (sb.ws / "out" / "logs-init.txt").read_text()))

    def test_a_flow_that_cannot_run_still_seeds_a_verdict(self):
        sb = Sandbox(self)  # no tools at all, and an install with no flow.sh
        (sb.pkg / "toolchain" / "flow.sh").unlink()
        r = sb.run([sb.pkg / "toolchain" / "init-workspace.sh"], HARNESS_DSH_DIR=sb.pkg)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("flow.sh", (sb.ws / "out" / "logs-init.txt").read_text())
        verdict = json.loads((sb.ws / ".harness" / "verdict.json").read_text())
        self.assertEqual((verdict["ready"], verdict["artifact"]), (False, "out/blink.report.json"))


class ViewerSh(unittest.TestCase):
    def test_needs_a_port_and_a_workspace(self):
        sb = Sandbox(self, stubs=("node",))
        r = sb.run([sb.pkg / "viewer.sh"], HARNESS_WORKSPACE=sb.ws)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("HARNESS_VIEWER_PORT", r.stderr)
        r = sb.run([sb.pkg / "viewer.sh"], HARNESS_VIEWER_PORT=4100)
        self.assertIn("HARNESS_WORKSPACE", r.stderr)
        self.assertEqual(sb.called(), [])

    def test_runs_the_server_beside_it_from_anywhere(self):
        sb = Sandbox(self, stubs=("node",))
        r = sb.run(["../install/viewer.sh"], HARNESS_VIEWER_PORT=4100, HARNESS_WORKSPACE=sb.ws)
        self.assertEqual(r.returncode, 0, r.stderr)
        [call] = sb.called()
        node, server = call.split(" ", 1)
        self.assertEqual((node, os.path.realpath(server)), ("node", os.path.realpath(sb.pkg / "viewer.mjs")))
        self.assertTrue(os.path.isabs(server))


REAL = ("iverilog", "vvp", "yosys", "nextpnr-ice40", "icepack")
REAL_PATH = f"{os.environ.get('PATH', '')}:/opt/homebrew/bin:/usr/local/bin"


@unittest.skipUnless(all(shutil.which(t, path=REAL_PATH) for t in REAL), "the FPGA flow is not installed")
class RealFlow(unittest.TestCase):
    def test_the_starter_design_goes_all_the_way_to_a_bitstream(self):
        root = Path(tempfile.mkdtemp(prefix="yosys-flow-"))
        self.addCleanup(shutil.rmtree, root, True)
        ws = root / "ws"
        shutil.copytree(PKG / "template", ws)
        env = {k: v for k, v in os.environ.items() if k not in SCRUB}
        env.update(PATH=REAL_PATH)
        r = subprocess.run([str(PKG / "toolchain" / "flow.sh"), "blink"], cwd=ws, env=env,
                           capture_output=True, text=True, timeout=600)
        report = json.loads((ws / "out" / "blink.report.json").read_text())
        states = {s["id"]: s["state"] for s in report["steps"]}
        self.assertEqual({k: states[k] for k in ("sim", "waves", "synth", "schematic", "pnr", "pack")},
                         dict.fromkeys(("sim", "waves", "synth", "schematic", "pnr", "pack"), "done"), r.stdout[-3000:])
        self.assertTrue(report["simulation"]["passed"])
        self.assertGreater(report["synthesis"]["cells"], 0)
        self.assertEqual(report["pnr"]["utilization"][0]["id"], "ICESTORM_LC")
        self.assertGreater(report["bitstream"]["bytes"], 0)
        if (PKG / "node_modules" / ".bin" / "netlistsvg").exists():
            self.assertEqual(states["svg"], "done")
            self.assertTrue((ws / "out" / "blink.svg").read_text().lstrip().startswith("<svg"))
            self.assertTrue(report["ready"], report["findings"])
            self.assertEqual(r.returncode, 0)
        else:  # setup.sh has not been run in this checkout: the drawing is the one thing missing
            self.assertEqual([f["kind"] for f in report["findings"]], ["svg"])
            self.assertEqual(r.returncode, 1)


if __name__ == "__main__":
    unittest.main()
