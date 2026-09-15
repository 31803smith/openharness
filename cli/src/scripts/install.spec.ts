import { spawnSync } from "child_process";
import { join } from "path";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { describe, expect, it } from "vitest";

// vitest runs from cli/, so this is cli/scripts/install.sh — the file published to the CDN.
const installer = join(process.cwd(), "scripts", "install.sh");

const writeCommand = (directory: string, name: string, lines: string[]) => {
  const path = join(directory, name);
  writeFileSync(path, ["#!/bin/sh", ...lines, ""].join("\n"));
  chmodSync(path, 0o700);
};

// What the CLI runs on Linux besides tmux — the only other command step 1 asks about.
const writeLinuxHostCommands = (directory: string) => {
  writeCommand(directory, "ps", ["exit 0"]);
};

// Step 1 of the script — the host-requirements ladder — as one runnable unit.
const hostSetupOf = (source: string) =>
  source.slice(source.indexOf("require_command()"), source.indexOf("# 2. Resolve the Node"));

// The download-tools check that guards the Node download, with the helpers it calls.
const downloadToolsOf = (source: string) =>
  source.slice(source.indexOf("require_command()"), source.indexOf("tmux_runs()")) +
  source.slice(
    source.indexOf("  # Fetching, unpacking and verifying the runtime"),
    source.indexOf("  # sha256 is the one tool"),
  );

describe("scripts/install.sh command contract", () => {
  it("rejects a legacy machine-token argument before installing", () => {
    const result = spawnSync("sh", [installer, "legacy-token"], { encoding: "utf8" });

    expect(result.status).toBe(2);
    expect(result.stderr).toContain("no longer accepts a machine token");
    expect(result.stderr).toContain("harness login && harness start");
  });

  it("accepts only standalone default, explicit desktop mode or host mode", () => {
    const source = readFileSync(installer, "utf8");
    const parser = source.slice(0, source.indexOf('METADATA_URL='));

    const standalone = spawnSync("/bin/sh", ["-s"], {
      encoding: "utf8",
      input: parser,
    });
    const desktop = spawnSync("/bin/sh", ["-s", "--", "--desktop"], {
      encoding: "utf8",
      input: parser,
    });
    const host = spawnSync("/bin/sh", ["-s", "--", "--host"], {
      encoding: "utf8",
      input: parser,
    });
    const extra = spawnSync(
      "/bin/sh",
      ["-s", "--", "--desktop", "legacy-token"],
      { encoding: "utf8", input: parser },
    );

    expect(standalone.status).toBe(0);
    expect(desktop.status).toBe(0);
    expect(host.status).toBe(0);
    expect(extra.status).toBe(2);
    expect(extra.stderr).toContain("accepts no additional arguments");
  });

  it("accepts a desktop-supplied Node runtime and pins the launcher to it", () => {
    const source = readFileSync(installer, "utf8");

    expect(source).toContain('NODE_BIN="${HARNESS_NODE_BINARY:-}"');
    expect(source).toContain('HARNESS_NODE_BINARY="$NODE_BIN"');
    expect(source).toContain("const shellQuote");
    expect(source).toContain("exec ' + shellQuote(NODE)");
  });

  // The CLI runs on the runtime under ~/.harness/runtime, never on whatever `node` PATH happens to
  // resolve — the same rule the desktop app follows, so one cli.js is never driven by two Nodes.
  it("installs its own Node runtime rather than requiring one", () => {
    const source = readFileSync(installer, "utf8");

    expect(source).toContain("harness/runtime/metadata.json");
    expect(source).toContain('CURRENT_NODE_FILE="$RUNTIME_DIR/current-node"');
    // The runtime is recorded for the desktop app to find, and only after it has answered.
    expect(source).toContain('printf \'%s\\n\' "$NODE_BIN" > "$CURRENT_NODE_FILE"');
    // No Node yet at that point, so the checksum has to be taken with the platform's own tool.
    expect(source).toContain("shasum -a 256");
    expect(source).toContain("sha256sum");
    // The old behaviour — bail out and tell the user to go install Node — must not come back.
    expect(source).not.toContain("brew install node");
    expect(source).not.toContain("deb.nodesource.com");
  });

  it("refuses an unverified Node archive", () => {
    const source = readFileSync(installer, "utf8");

    expect(source).toContain('if [ "$node_got" != "$node_sha" ]; then');
    expect(source).toContain("failed checksum verification");
  });

  it("prepares and verifies required tmux before installing Node or Harness", () => {
    const source = readFileSync(installer, "utf8");
    const tmuxStep = source.indexOf("# 1. Host requirements");
    const nodeStep = source.indexOf("# 2. Resolve the Node");
    const cliStep = source.indexOf("# 3. Fetch manifest");

    expect(tmuxStep).toBeGreaterThan(-1);
    expect(nodeStep).toBeGreaterThan(tmuxStep);
    expect(cliStep).toBeGreaterThan(nodeStep);
    expect(source).toContain("/usr/bin/xcrun --find clang");
    expect(source).toContain(
      "sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer",
    );
    expect(source).toContain("xcode-select --install");
    // An unaccepted Xcode licence makes xcrun fail exactly like an unselected directory; only
    // one of them is fixed by xcode-select, so the licence is checked and accepted first.
    expect(source).toContain("/usr/bin/xcodebuild -license check");
    expect(source).toContain("sudo /usr/bin/xcodebuild -license accept");
    expect(source.indexOf("-license accept")).toBeLessThan(
      source.indexOf("sudo xcode-select --switch"),
    );
    expect(source).toContain("Homebrew installation failed");
    expect(source).toContain("brew install tmux");
    expect(source).toContain("install_with_apt $missing_host_packages");
    expect(source).toContain('if [ "$(id -u)" -eq 0 ]; then');
    expect(source).toContain('sudo apt-get "$@"');
    expect(source).not.toContain("sudo apt-get update &&");
    expect(source).toContain("Could not install tmux via Homebrew");
    expect(source).toContain("tmux is required but did not pass verification");
    expect(source).toContain("exit 22");
  });

  // The ladder, in source order: tmux is asked about first, Homebrew only when tmux is missing, the
  // Apple developer tools only when Homebrew is missing too.
  it("asks about Homebrew only without tmux, and about Xcode only without Homebrew", () => {
    const source = readFileSync(installer, "utf8");
    const darwin = source.slice(source.indexOf("  Darwin)"), source.indexOf("  Linux)"));

    const tmuxCheck = darwin.indexOf("if tmux_runs; then");
    const brewCheck = darwin.indexOf('if ! command -v brew >/dev/null 2>&1; then');
    const xcrunCheck = darwin.indexOf("/usr/bin/xcrun --find clang");
    expect(tmuxCheck).toBeGreaterThan(-1);
    expect(brewCheck).toBeGreaterThan(tmuxCheck);
    expect(xcrunCheck).toBeGreaterThan(brewCheck);
  });

  it("does nothing on a Mac that already runs tmux", () => {
    const source = readFileSync(installer, "utf8");
    const hostSetup = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-mac-tmux-"));
    const invoked = join(scratch, "brew-invoked");

    try {
      writeCommand(scratch, "uname", ["printf 'Darwin\\n'"]);
      writeCommand(scratch, "tmux", ["printf 'tmux 3.6\\n'"]);
      writeCommand(scratch, "brew", [`: > '${invoked}'`, "exit 99"]);
      writeCommand(scratch, "sudo", [`: > '${invoked}'`, "exit 99"]);
      writeCommand(scratch, "xcode-select", [`: > '${invoked}'`, "exit 99"]);

      const result = spawnSync("/bin/sh", ["-c", hostSetup], {
        encoding: "utf8",
        env: { ...process.env, INSTALL_MODE: "standalone", PATH: scratch },
      });

      expect(result.status).toBe(0);
      expect(result.stdout).toContain("tmux ready");
      expect(result.stdout).not.toContain("Homebrew");
      expect(() => readFileSync(invoked, "utf8")).toThrow();
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("installs tmux with an existing Homebrew and never looks for Xcode", () => {
    const source = readFileSync(installer, "utf8");
    const hostSetup = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-mac-brew-"));
    const invocations = join(scratch, "brew-invocations");
    const developerTools = join(scratch, "developer-tools-touched");
    const fakeTmux = join(scratch, "tmux");

    try {
      writeCommand(scratch, "uname", ["printf 'Darwin\\n'"]);
      writeCommand(scratch, "brew", [
        `printf '%s\\n' "$*" >> '${invocations}'`,
        `if [ "$1" = "shellenv" ]; then exit 0; fi`,
        `printf '%s\\n' '#!/bin/sh' 'printf "tmux 3.6\\\\n"' > '${fakeTmux}'`,
        `/bin/chmod 700 '${fakeTmux}'`,
      ]);
      writeCommand(scratch, "sudo", [`: > '${developerTools}'`, "exit 99"]);
      writeCommand(scratch, "xcode-select", [`: > '${developerTools}'`, "exit 99"]);

      const result = spawnSync("/bin/sh", ["-c", hostSetup], {
        encoding: "utf8",
        env: { ...process.env, INSTALL_MODE: "standalone", PATH: scratch },
      });

      expect(result.status).toBe(0);
      expect(readFileSync(invocations, "utf8")).toContain("install tmux\n");
      expect(result.stdout).not.toContain("Apple developer tools");
      expect(() => readFileSync(developerTools, "utf8")).toThrow();
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("host mode stops after the host requirements", () => {
    const source = readFileSync(installer, "utf8");
    const hostSetup = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-host-mode-"));

    try {
      writeCommand(scratch, "uname", ["printf 'Darwin\\n'"]);
      writeCommand(scratch, "tmux", ["printf 'tmux 3.6\\n'"]);

      const result = spawnSync("/bin/sh", ["-c", `${hostSetup}\necho REACHED-NODE-STEP`], {
        encoding: "utf8",
        env: { ...process.env, INSTALL_MODE: "host", PATH: scratch },
      });

      expect(result.status).toBe(0);
      expect(result.stdout).toContain("Host requirements ready");
      expect(result.stdout).not.toContain("REACHED-NODE-STEP");
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("installs nothing on a Linux host that already runs tmux and ps", () => {
    const source = readFileSync(installer, "utf8");
    const hostSetup = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-linux-ready-"));
    const invoked = join(scratch, "apt-invoked");

    try {
      writeLinuxHostCommands(scratch);
      writeCommand(scratch, "id", ["printf '0\\n'"]);
      writeCommand(scratch, "uname", ["printf 'Linux\\n'"]);
      writeCommand(scratch, "tmux", ["printf 'tmux 3.6\\n'"]);
      // curl is a download tool, not a host requirement: its absence is no business of step 1.
      writeCommand(scratch, "apt-get", [`: > '${invoked}'`, "exit 99"]);

      const result = spawnSync("/bin/sh", ["-c", hostSetup], {
        encoding: "utf8",
        env: {
          ...process.env,
          INSTALL_MODE: "standalone",
          DISPLAY: "",
          WAYLAND_DISPLAY: "",
          PATH: scratch,
        },
      });

      expect(result.status).toBe(0);
      expect(result.stdout).toContain("tmux ready");
      expect(() => readFileSync(invoked, "utf8")).toThrow();
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("installs the download tools only when the runtime is downloaded", () => {
    const source = readFileSync(installer, "utf8");
    // The check lives inside the download branch, after managed-runtime reuse is ruled out.
    const download = source.indexOf('if [ -z "$NODE_BIN" ]; then\n\n  # Fetching');
    const reuse = source.indexOf('if [ -z "$NODE_BIN" ] && [ -r "$CURRENT_NODE_FILE" ]');
    expect(reuse).toBeGreaterThan(-1);
    expect(download).toBeGreaterThan(reuse);
    expect(source.slice(0, download)).not.toContain("require_command curl");

    const downloadTools = downloadToolsOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-download-tools-"));
    const invocations = join(scratch, "apt-invocations");
    const fakeCurl = join(scratch, "curl");

    try {
      for (const command of ["tar", "sed", "awk", "sha256sum"]) {
        writeCommand(scratch, command, ["exit 0"]);
      }
      writeCommand(scratch, "id", ["printf '0\\n'"]);
      writeCommand(scratch, "uname", ["printf 'Linux\\n'"]);
      writeCommand(scratch, "apt-get", [
        `printf '%s\\n' "$*" >> '${invocations}'`,
        `printf '%s\\n' '#!/bin/sh' 'exit 0' > '${fakeCurl}'`,
        `/bin/chmod 700 '${fakeCurl}'`,
      ]);

      const result = spawnSync("/bin/sh", ["-c", downloadTools], {
        encoding: "utf8",
        env: { ...process.env, PATH: scratch },
      });

      expect(result.status).toBe(0);
      expect(readFileSync(invocations, "utf8")).toBe("install -y curl\n");
      expect(result.stdout).toContain("tools needed to download the runtime");
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("installs tmux through sudo without refreshing usable package indexes", () => {
    const source = readFileSync(installer, "utf8");
    const tmuxStep = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-tmux-user-"));
    const invocation = join(scratch, "sudo-invocation");
    const fakeTmux = join(scratch, "tmux");

    try {
      writeLinuxHostCommands(scratch);
      writeCommand(scratch, "id", ["printf '1000\\n'"]);
      writeCommand(scratch, "uname", ["printf 'Linux\\n'"]);
      writeCommand(scratch, "apt-get", ["exit 99"]);
      writeCommand(scratch, "sudo", [
        `printf '%s\\n' "$*" > '${invocation}'`,
        `printf '%s\\n' '#!/bin/sh' 'printf "tmux 3.6\\\\n"' > '${fakeTmux}'`,
        `/bin/chmod 700 '${fakeTmux}'`,
      ]);

      const result = spawnSync("/bin/sh", ["-c", tmuxStep], {
        encoding: "utf8",
        env: {
          ...process.env,
          INSTALL_MODE: "standalone",
          DISPLAY: "",
          WAYLAND_DISPLAY: "",
          PATH: scratch,
        },
      });

      expect(result.status).toBe(0);
      expect(readFileSync(invocation, "utf8")).toBe("apt-get install -y tmux\n");
      expect(result.stdout).toContain("tmux ready");
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("installs as root without sudo and retries after a failed index refresh", () => {
    const source = readFileSync(installer, "utf8");
    const tmuxStep = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-tmux-root-"));
    const invocations = join(scratch, "apt-invocations");
    const firstAttempt = join(scratch, "first-attempt");
    const fakeTmux = join(scratch, "tmux");

    try {
      writeLinuxHostCommands(scratch);
      writeCommand(scratch, "id", ["printf '0\\n'"]);
      writeCommand(scratch, "uname", ["printf 'Linux\\n'"]);
      writeCommand(scratch, "apt-get", [
        `printf '%s\\n' "$*" >> '${invocations}'`,
        `if [ "$1" = "update" ]; then exit 77; fi`,
        `if [ ! -f '${firstAttempt}' ]; then : > '${firstAttempt}'; exit 1; fi`,
        `printf '%s\\n' '#!/bin/sh' 'printf "tmux 3.6\\\\n"' > '${fakeTmux}'`,
        `/bin/chmod 700 '${fakeTmux}'`,
      ]);

      const result = spawnSync("/bin/sh", ["-c", tmuxStep], {
        encoding: "utf8",
        env: {
          ...process.env,
          INSTALL_MODE: "standalone",
          DISPLAY: "",
          WAYLAND_DISPLAY: "",
          PATH: scratch,
        },
      });

      expect(result.status).toBe(0);
      expect(readFileSync(invocations, "utf8")).toBe(
        "install -y tmux\nupdate\ninstall -y tmux\n",
      );
      expect(result.stdout).toContain("tmux ready");
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("requires only the active Linux desktop clipboard helper before Node", () => {
    const source = readFileSync(installer, "utf8");
    const wayland = source.indexOf('clipboard_command="wl-copy"');
    const x11 = source.indexOf('clipboard_command="xclip"');
    const nodeStep = source.indexOf("# 2. Resolve the Node");

    expect(wayland).toBeGreaterThan(-1);
    expect(x11).toBeGreaterThan(wayland);
    expect(nodeStep).toBeGreaterThan(x11);
    expect(source).toContain('if [ -n "${WAYLAND_DISPLAY:-}" ]; then');
    expect(source).toContain('elif [ -n "${DISPLAY:-}" ]; then');
    expect(source).toContain('exit 23');
    expect(source).not.toContain("install_with_apt xclip wl-clipboard");
  });

  it("installs xclip for X11 and verifies it", () => {
    const source = readFileSync(installer, "utf8");
    const hostSetup = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-xclip-root-"));
    const invocations = join(scratch, "apt-invocations");
    const fakeXclip = join(scratch, "xclip");

    try {
      writeLinuxHostCommands(scratch);
      writeCommand(scratch, "id", ["printf '0\\n'"]);
      writeCommand(scratch, "uname", ["printf 'Linux\\n'"]);
      writeCommand(scratch, "tmux", ["printf 'tmux 3.6\\n'"]);
      writeCommand(scratch, "apt-get", [
        `printf '%s\\n' "$*" >> '${invocations}'`,
        `printf '%s\\n' '#!/bin/sh' 'exit 0' > '${fakeXclip}'`,
        `/bin/chmod 700 '${fakeXclip}'`,
      ]);

      const result = spawnSync("/bin/sh", ["-c", hostSetup], {
        encoding: "utf8",
        env: {
          ...process.env,
          INSTALL_MODE: "standalone",
          DISPLAY: ":0",
          WAYLAND_DISPLAY: "",
          PATH: scratch,
        },
      });

      expect(result.status).toBe(0);
      expect(readFileSync(invocations, "utf8")).toBe("install -y xclip\n");
      expect(result.stdout).toContain("Linux image clipboard ready (xclip)");
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("does not install clipboard packages on a headless Linux host", () => {
    const source = readFileSync(installer, "utf8");
    const hostSetup = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-headless-root-"));
    const invoked = join(scratch, "apt-invoked");

    try {
      writeLinuxHostCommands(scratch);
      writeCommand(scratch, "id", ["printf '0\\n'"]);
      writeCommand(scratch, "uname", ["printf 'Linux\\n'"]);
      writeCommand(scratch, "tmux", ["printf 'tmux 3.6\\n'"]);
      writeCommand(scratch, "apt-get", [`: > '${invoked}'`, "exit 99"]);

      const result = spawnSync("/bin/sh", ["-c", hostSetup], {
        encoding: "utf8",
        env: {
          ...process.env,
          INSTALL_MODE: "standalone",
          DISPLAY: "",
          WAYLAND_DISPLAY: "",
          PATH: scratch,
        },
      });

      expect(result.status).toBe(0);
      expect(result.stdout).toContain("native image clipboard is not applicable");
      expect(() => readFileSync(invoked, "utf8")).toThrow();
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("fails before Node when the active Wayland helper cannot be installed", () => {
    const source = readFileSync(installer, "utf8");
    const hostSetup = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-wayland-fail-"));

    try {
      writeLinuxHostCommands(scratch);
      writeCommand(scratch, "id", ["printf '0\\n'"]);
      writeCommand(scratch, "uname", ["printf 'Linux\\n'"]);
      writeCommand(scratch, "tmux", ["printf 'tmux 3.6\\n'"]);
      writeCommand(scratch, "apt-get", ["exit 88"]);

      const result = spawnSync("/bin/sh", ["-c", hostSetup], {
        encoding: "utf8",
        env: {
          ...process.env,
          INSTALL_MODE: "standalone",
          DISPLAY: ":0",
          WAYLAND_DISPLAY: "wayland-0",
          PATH: scratch,
        },
      });

      expect(result.status).toBe(23);
      expect(result.stderr).toContain("Could not install wl-clipboard");
      expect(result.stderr).not.toContain("xclip");
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it("desktop mode skips all host package and tmux work", () => {
    const source = readFileSync(installer, "utf8");
    const hostSetup = hostSetupOf(source);
    const scratch = mkdtempSync(join(tmpdir(), "harness-desktop-mode-"));
    const invoked = join(scratch, "host-command-invoked");

    try {
      for (const command of ["uname", "sudo", "apt-get", "tmux", "brew"]) {
        writeCommand(scratch, command, [`: > '${invoked}'`, "exit 99"]);
      }

      const result = spawnSync("/bin/sh", ["-c", hostSetup], {
        encoding: "utf8",
        env: { ...process.env, INSTALL_MODE: "desktop", PATH: scratch },
      });

      expect(result.status).toBe(0);
      expect(result.stdout).toContain("Desktop mode");
      expect(() => readFileSync(invoked, "utf8")).toThrow();
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });
});
