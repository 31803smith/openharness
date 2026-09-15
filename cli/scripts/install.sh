#!/bin/sh
# harness — one-line installer, served from the CDN at
# https://cdn.autonomous.ai/harness/cli/install.sh (source of truth: THIS file, cli/scripts/install.sh in
# the autonomous-harness repo — published with `make upload-cli-install-sh` from the repo root, and
# checked by cli/src/scripts/install.spec.ts). Not the same thing as cli/scripts/install-cli.sh, which
# installs the CLI from a working tree for local development and publishes nothing.
# The website (autonomous-code, apps/web) still answers the OLD URL, https://harness.autonomous.ai/cli/
# install.sh, but only as a redirect to the CDN one (its next.config.js) — kept for anyone with the old
# link already saved.
#   curl -fsSL https://cdn.autonomous.ai/harness/cli/install.sh | bash
#   curl -fsSL https://cdn.autonomous.ai/harness/cli/install.sh | sh -s -- --desktop  # Desktop: runtime + CLI only
#   curl -fsSL https://cdn.autonomous.ai/harness/cli/install.sh | sh -s -- --host     # Desktop: host requirements only
#   harness login
#   harness start
#
# Downloads the self-contained CLI bundle from the public GCS manifest and installs a `harness` command.
# Login and start are deliberately separate: login saves a native SSO session, while start launches the
# adapter from that session. The running daemon auto-updates itself thereafter (polls the same manifest).
# There is no system Node prerequisite. The CLI is plain JS (no native binary, no code-signing) and it runs on a
# checksum-verified Node this installer puts in ~/.harness/runtime — the same runtime Desktop Harness
# manages, shared on purpose so one cli.js is never run by two different Nodes. Your own Node and nvm
# are neither required nor touched.
#
# What the CLI RUNS is a short list — tmux (its only terminal backend), `ps`, and on a Linux desktop
# the clipboard helper for the active display — and step 1 checks exactly that list. Everything else
# here (Homebrew, the Apple developer tools, apt, curl/tar/sed/awk/sha256sum) is only a way of
# obtaining one of those or of downloading the runtime, and is looked at only when the thing it
# obtains is missing: a Mac with tmux never hears about Homebrew, a Mac with Homebrew never hears
# about Xcode, and the download tools are checked only when a runtime is actually downloaded.
# Desktop mode (`--desktop`) trusts the app's own host pre-flight and skips step 1; host mode
# (`--host`) is the app handing step 1 to a real terminal for its password prompts and stops after it.
# The runtime's absolute path is baked into the launcher, so a Finder launch — where PATH is
# launchd's bare /usr/bin:/bin:/usr/sbin:/sbin — resolves the CLI exactly like a terminal does.
# POSIX sh (so `| sh` and `| bash` both work).
set -eu

# No argument is the complete standalone/server installer. Desktop owns host pre-flight and passes
# --desktop so this script installs only the managed runtime and CLI instead of asking twice for the
# same package-manager/admin work — or --host for the opposite half.
INSTALL_MODE=standalone
case "${1:-}" in
  "") ;;
  --desktop)
    INSTALL_MODE=desktop
    shift
    ;;
  --host)
    INSTALL_MODE=host
    shift
    ;;
  *)
    echo "✗ Unsupported installer argument: $1" >&2
    echo "  This installer no longer accepts a machine token." >&2
    echo "  Run the installer without arguments, then: harness login && harness start" >&2
    exit 2
    ;;
esac
if [ "$#" -gt 0 ]; then
  echo "✗ $INSTALL_MODE mode accepts no additional arguments." >&2
  echo "✗ This installer no longer accepts a machine token." >&2
  exit 2
fi

METADATA_URL="${HARNESS_METADATA_URL:-https://storage.googleapis.com/s3-autonomous-upgrade-3/harness/cli/metadata.json}"
# Published by `make upload-node-runtime` in the desktop repo; the desktop app reads the same manifest
# (its --dart-define is spelled the same) so both installers land on identical bytes.
RUNTIME_METADATA_URL="${HARNESS_RUNTIME_METADATA_URL:-https://storage.googleapis.com/s3-autonomous-upgrade-3/harness/runtime/metadata.json}"
HARNESS_KEY="${HARNESS_KEY:-cli}"
CLI_DIR="$HOME/.harness/cli"
RUNTIME_DIR="$HOME/.harness/runtime"
CURRENT_NODE_FILE="$RUNTIME_DIR/current-node"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="$BIN_DIR/harness"

# 1. Host requirements (standalone and --host). The CLI runs tmux, `ps`, and on a Linux desktop the
#    clipboard helper — those are checked, and only what is missing is obtained. This installer
#    already runs in a terminal, so package-manager password prompts stay with the OS — never Harness.
require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "✗ Required system tool is missing: $1" >&2
    exit 11
  }
}

apt_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    apt-get "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get "$@"
  else
    echo "✗ Installing system packages needs root access, but sudo is unavailable." >&2
    return 1
  fi
}

install_with_apt() {
  if apt_as_root install -y "$@"; then
    return 0
  fi
  echo "▸ Refreshing package indexes before retrying"
  apt_as_root update || true
  apt_as_root install -y "$@"
}

tmux_runs() {
  command -v tmux >/dev/null 2>&1 && tmux -V >/dev/null 2>&1
}

if [ "$INSTALL_MODE" != "desktop" ]; then
case "$(uname -s)" in
  Darwin)
    if tmux_runs; then
      : # tmux runs. Homebrew and the Apple developer tools are how it would have been installed;
        # with it here they are nobody's business, and neither is looked at.
    else
      # A Homebrew installed for a different shell is still installed.
      if ! command -v brew >/dev/null 2>&1; then
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
      fi
      if ! command -v brew >/dev/null 2>&1; then
        # Homebrew's own installer needs the Apple developer tools; this is the only place they matter.
        if ! /usr/bin/xcrun --find clang >/dev/null 2>&1; then
          echo "▸ Apple developer tools are required by Homebrew (Xcode or Command Line Tools)."
          if [ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]; then
            # xcrun answers "not ready" for two different reasons, and only one of them is the
            # developer directory. An unaccepted Xcode licence exits 69 and no amount of
            # xcode-select fixes it.
            if ! /usr/bin/xcodebuild -license check >/dev/null 2>&1; then
              echo "  Xcode is installed but its licence has not been accepted."
              echo "  macOS may ask for your password to accept it."
              sudo /usr/bin/xcodebuild -license accept
            fi
            if ! /usr/bin/xcrun --find clang >/dev/null 2>&1; then
              echo "  Xcode is installed but is not the active developer directory."
              echo "  macOS may ask for your password to select it."
              sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
            fi
          else
            echo "  macOS will open its installer now. Finish it, then run this Harness installer again."
            xcode-select --install >/dev/null 2>&1 || true
            exit 20
          fi
          /usr/bin/xcrun --find clang >/dev/null 2>&1 || {
            echo "✗ Apple developer tools are selected but are not usable." >&2
            exit 20
          }
        fi
        echo "▸ Installing Homebrew (macOS may ask for your password)"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
          echo "✗ Homebrew installation failed. Review the output above, then retry." >&2
          exit 21
        }
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
        command -v brew >/dev/null 2>&1 || {
          echo "✗ Homebrew was installed but is not available to this shell." >&2
          exit 21
        }
      fi
      echo "▸ Installing tmux via Homebrew"
      brew install tmux || {
        echo "✗ Could not install tmux via Homebrew. Retry with: brew install tmux" >&2
        exit 22
      }
    fi
    ;;
  Linux)
    missing_host_packages=""
    tmux_runs || missing_host_packages="$missing_host_packages tmux"
    command -v ps >/dev/null 2>&1 || missing_host_packages="$missing_host_packages procps"
    # Native image paste needs the helper for the display protocol this process will use. A
    # genuinely headless server has no OS clipboard, so installing either package there would add a
    # sudo prompt without adding a capability; the CLI deliberately uses its file-path fallback.
    clipboard_command=""
    clipboard_package=""
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
      clipboard_command="wl-copy"
      clipboard_package="wl-clipboard"
    elif [ -n "${DISPLAY:-}" ]; then
      clipboard_command="xclip"
      clipboard_package="xclip"
    else
      echo "▸ No X11 or Wayland display detected; native image clipboard is not applicable."
    fi
    if [ -n "$clipboard_command" ] && ! command -v "$clipboard_command" >/dev/null 2>&1; then
      missing_host_packages="$missing_host_packages $clipboard_package"
    fi
    if [ -n "$missing_host_packages" ]; then
      command -v apt-get >/dev/null 2>&1 || {
        echo "✗ Required Linux packages are missing:$missing_host_packages" >&2
        echo "  Automatic install supports apt-based Linux only; install them with this distribution's package manager, then retry." >&2
        exit 22
      }
      echo "▸ Installing required Linux packages (you may be asked for your password):$missing_host_packages"
      # Intentional word splitting: this list contains only package names selected above.
      # shellcheck disable=SC2086
      install_with_apt $missing_host_packages || {
        echo "✗ Could not install${missing_host_packages} via apt-get." >&2
        echo "  Retry with: sudo apt-get install -y$missing_host_packages" >&2
        # 23 is the clipboard helper's own code, kept for a transaction that was only that.
        if [ "$missing_host_packages" = " $clipboard_package" ]; then exit 23; fi
        exit 22
      }
    fi
    command -v ps >/dev/null 2>&1 || {
      echo "✗ ps is required but did not pass verification." >&2
      exit 22
    }
    if [ -n "$clipboard_command" ]; then
      command -v "$clipboard_command" >/dev/null 2>&1 || {
        echo "✗ $clipboard_command is required but did not pass verification." >&2
        exit 23
      }
      echo "✓ Linux image clipboard ready ($clipboard_command)"
    fi
    ;;
  *)
    echo "✗ Automatic Harness installation supports macOS and Linux only." >&2
    exit 10
    ;;
esac

tmux_runs || {
  echo "✗ tmux is required but did not pass verification." >&2
  exit 22
}
echo "✓ tmux ready ($(tmux -V))"
if [ "$INSTALL_MODE" = "host" ]; then
  echo "✓ Host requirements ready."
  exit 0
fi
else
  echo "▸ Desktop mode: trusting the app's host pre-flight; skipping system packages and tmux setup."
fi

# 2. Resolve the Node that will run the CLI (and this installer's own JSON parse + sha256 verify in
#    step 3). The CLI runs on the MANAGED runtime under ~/.harness/runtime, not on whatever Node the
#    computer happens to have:
#      1. $HARNESS_NODE_BINARY — Desktop Harness handing over the runtime it just validated.
#      2. ~/.harness/runtime/current-node — the managed runtime, if it is already here.
#      3. otherwise, download it.
#    A Node on PATH is used only as a last resort, on a platform we publish no runtime for.
#
#    Why not prefer the user's own Node: it is the version-drift bug in a different shirt. A CLI
#    driven from the desktop app and from a terminal must be ONE cli.js on ONE Node, and a `node`
#    that PATH resolves is none of stable, shared, or ours — it moves with nvm, it differs between a
#    Finder launch and a Terminal launch, and it can be upgraded out from under a running daemon.
#    Nothing outside ~/.harness is read or changed either way; the user's own Node is left alone.
#
#    Everything in this step must run in plain POSIX sh: there is no Node yet to lean on.

# Prints the major version of $1, or nothing when it cannot be run.
node_major() {
  "$1" -e 'process.stdout.write(String(process.versions.node.split(".")[0]))' 2>/dev/null || true
}

node_is_usable() {
  [ -n "${1:-}" ] || return 1
  [ -x "$1" ] || return 1
  _major="$(node_major "$1")"
  [ -n "$_major" ] || return 1
  [ "$_major" -ge 20 ] 2>/dev/null || return 1
  return 0
}

NODE_BIN="${HARNESS_NODE_BINARY:-}"
if [ -n "$NODE_BIN" ]; then
  # An explicit override is an instruction, not a hint: if it is unusable, say so rather than
  # quietly downloading a second runtime behind the caller's back.
  if [ ! -x "$NODE_BIN" ]; then
    echo "✗ HARNESS_NODE_BINARY is not an executable Node runtime: $NODE_BIN" >&2
    exit 1
  fi
  if ! node_is_usable "$NODE_BIN"; then
    echo "✗ HARNESS_NODE_BINARY is older than Node 20: $NODE_BIN ($("$NODE_BIN" -v 2>/dev/null || echo unknown))" >&2
    exit 1
  fi
fi

if [ -z "$NODE_BIN" ] && [ -r "$CURRENT_NODE_FILE" ]; then
  managed_node="$(cat "$CURRENT_NODE_FILE" 2>/dev/null || true)"
  # Only ever trust a path inside the runtime directory we own.
  case "$managed_node" in
    "$RUNTIME_DIR"/*)
      if node_is_usable "$managed_node"; then
        NODE_BIN="$managed_node"
        echo "▸ Using the managed Node runtime already installed ($("$NODE_BIN" -v))"
      fi
      ;;
  esac
fi

if [ -z "$NODE_BIN" ]; then
  # Fetch the same checksum-pinned runtime Desktop Harness uses. A Node already on PATH is
  # deliberately NOT preferred here — see the note in step 1 — but it is still the last resort on a
  # platform we publish no runtime for, so an exotic box keeps working instead of being locked out.
  node_platform=""
  case "$(uname -s)" in
    Darwin) node_os=darwin ;;
    Linux)  node_os=linux ;;
    *)      node_os="" ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) node_arch=arm64 ;;
    x86_64|amd64)  node_arch=x64 ;;
    *)             node_arch="" ;;
  esac
  [ -n "$node_os" ] && [ -n "$node_arch" ] && node_platform="$node_os-$node_arch"

  if [ -z "$node_platform" ]; then
    path_node="$(command -v node 2>/dev/null || true)"
    if [ -n "$path_node" ] && node_is_usable "$path_node"; then
      echo "▸ No managed Node runtime is published for $(uname -s)/$(uname -m) — using $path_node"
      NODE_BIN="$path_node"
    else
      echo "✗ No managed Node runtime is published for $(uname -s)/$(uname -m), and no Node >= 20 on PATH." >&2
      echo "  Install Node 20+ from https://nodejs.org, then re-run this installer." >&2
      exit 1
    fi
  fi
fi

if [ -z "$NODE_BIN" ]; then

  # Fetching, unpacking and verifying the runtime is the only work in this file that needs these
  # host tools (step 3 is Node, and Node needs none of them) — so they are asked for here, once the
  # download is known to be happening, and nowhere earlier. macOS ships them all; a minimal Linux
  # can lack curl, and that is what apt is for.
  if [ "$(uname -s)" = "Linux" ]; then
    missing_download_tools=""
    command -v curl >/dev/null 2>&1 || missing_download_tools="$missing_download_tools curl"
    command -v tar >/dev/null 2>&1 || missing_download_tools="$missing_download_tools tar"
    command -v sed >/dev/null 2>&1 || missing_download_tools="$missing_download_tools sed"
    command -v awk >/dev/null 2>&1 || missing_download_tools="$missing_download_tools gawk"
    command -v sha256sum >/dev/null 2>&1 || missing_download_tools="$missing_download_tools coreutils"
    if [ -n "$missing_download_tools" ]; then
      command -v apt-get >/dev/null 2>&1 || {
        echo "✗ Downloading the Node runtime needs tools this computer lacks:$missing_download_tools" >&2
        echo "  Automatic install supports apt-based Linux only; install them with this distribution's package manager, then retry." >&2
        exit 11
      }
      echo "▸ Installing the tools needed to download the runtime (you may be asked for your password):$missing_download_tools"
      # shellcheck disable=SC2086
      install_with_apt $missing_download_tools || {
        echo "✗ Could not install the download tools via apt-get." >&2
        exit 11
      }
    fi
  fi
  require_command curl
  require_command tar
  require_command sed
  require_command awk

  # sha256 is the one tool that genuinely differs between the two platforms, and it is needed
  # BEFORE Node exists to smooth it over — hence this pair rather than step 2's single JS path.
  if command -v shasum >/dev/null 2>&1; then
    sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256_of() { sha256sum "$1" | awk '{print $1}'; }
  else
    echo "✗ Need shasum or sha256sum to verify the Node download, and found neither." >&2
    exit 11
  fi

  echo "▸ Installing the Harness Node runtime into $RUNTIME_DIR"
  echo "  The CLI runs on its own Node so it behaves the same from a terminal and from the app."
  echo "  Your system Node, nvm and Homebrew are not read or changed."
  runtime_manifest="$(curl -fsSL "$RUNTIME_METADATA_URL")" || {
    echo "✗ Could not fetch the Node runtime manifest: $RUNTIME_METADATA_URL" >&2
    exit 1
  }
  # The manifest is our own, published one key per line; pull just this platform's object out and
  # read its fields. No jq/python dependency, which a bare machine may equally not have.
  runtime_entry="$(printf '%s\n' "$runtime_manifest" | sed -n "/\"$node_platform\"[[:space:]]*:[[:space:]]*{/,/}/p")"
  entry_field() {
    printf '%s\n' "$runtime_entry" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  }
  node_url="$(entry_field url)"
  node_sha="$(entry_field sha256)"
  node_root="$(entry_field archiveRoot)"
  node_version="$(entry_field version)"
  if [ -z "$node_url" ] || [ -z "$node_sha" ] || [ -z "$node_root" ] || [ -z "$node_version" ]; then
    echo "✗ The Node runtime manifest has no usable '$node_platform' entry." >&2
    exit 1
  fi

  mkdir -p "$RUNTIME_DIR"
  chmod 700 "$RUNTIME_DIR" 2>/dev/null || true
  node_target="$RUNTIME_DIR/node-$node_version-$node_platform"
  if [ ! -x "$node_target/bin/node" ]; then
    node_staging="$RUNTIME_DIR/.node-staging-$$"
    rm -rf "$node_staging"
    mkdir -p "$node_staging"
    # Staging never outlives this script, however it ends — a half-unpacked runtime that looked
    # complete would be worse than no runtime at all.
    trap 'rm -rf "$node_staging"' EXIT INT TERM
    echo "  ▸ downloading Node $node_version ($node_platform)…"
    curl -fsSL "$node_url" -o "$node_staging/node.tar.gz" || {
      echo "✗ Could not download $node_url" >&2
      exit 1
    }
    node_got="$(sha256_of "$node_staging/node.tar.gz")"
    if [ "$node_got" != "$node_sha" ]; then
      echo "✗ Node download failed checksum verification (expected $node_sha, got $node_got)" >&2
      exit 1
    fi
    tar -xzf "$node_staging/node.tar.gz" -C "$node_staging" || {
      echo "✗ Could not unpack the Node archive" >&2
      exit 1
    }
    [ -x "$node_staging/$node_root/bin/node" ] || {
      echo "✗ The Node archive has no $node_root/bin/node" >&2
      exit 1
    }
    mv "$node_staging/$node_root" "$node_target"
    rm -rf "$node_staging"
    trap - EXIT INT TERM
  fi

  NODE_BIN="$node_target/bin/node"
  if ! node_is_usable "$NODE_BIN"; then
    echo "✗ The installed Node runtime does not run on this computer: $NODE_BIN" >&2
    exit 1
  fi
  # Recorded last, and only once the binary has answered `--version`: this file is what Desktop
  # Harness reads to pick its runtime, so it must never name something that does not work.
  printf '%s\n' "$NODE_BIN" > "$CURRENT_NODE_FILE"
  chmod 600 "$CURRENT_NODE_FILE" 2>/dev/null || true
  echo "  ✓ installed Node $node_version → $node_target"
fi

# 3. Fetch manifest, download + sha256-verify cli.js & notify.mjs, install them + the launcher (all in
#    Node so it works identically on macOS/Linux without shasum/sha256sum差异).
echo "▸ Installing harness from $METADATA_URL"
HARNESS_METADATA_URL="$METADATA_URL" HARNESS_KEY="$HARNESS_KEY" HARNESS_NODE_BINARY="$NODE_BIN" "$NODE_BIN" <<'HARNESSJS'
const fs = require('fs'), os = require('os'), path = require('path'), crypto = require('crypto')
const META = process.env.HARNESS_METADATA_URL, KEY = process.env.HARNESS_KEY, NODE = process.env.HARNESS_NODE_BINARY
const dir = path.join(os.homedir(), '.harness', 'cli')
const bin = path.join(os.homedir(), '.local', 'bin')
;(async () => {
  const res = await fetch(META)
  if (!res.ok) throw new Error('could not fetch manifest (HTTP ' + res.status + ')')
  const entry = (await res.json())[KEY]
  if (!entry || !entry.version || !entry.cli || !entry.notify) throw new Error("manifest has no valid '" + KEY + "' entry")
  fs.mkdirSync(dir, { recursive: true })
  fs.mkdirSync(bin, { recursive: true })
  const fetchVerified = async (ref, name) => {
    const r = await fetch(ref.url)
    if (!r.ok) throw new Error('HTTP ' + r.status + ' for ' + ref.url)
    const buf = Buffer.from(await r.arrayBuffer())
    const got = crypto.createHash('sha256').update(buf).digest('hex')
    if (got.toLowerCase() !== String(ref.sha256).toLowerCase()) throw new Error('sha256 mismatch for ' + name)
    fs.writeFileSync(path.join(dir, name), buf)
  }
  await fetchVerified(entry.cli, 'cli.js')
  await fetchVerified(entry.notify, 'notify.mjs')
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ type: 'module' }) + '\n')
  const shellQuote = value => "'" + value.replaceAll("'", "'\\''") + "'"
  fs.writeFileSync(path.join(bin, 'harness'), '#!/bin/sh\nexec ' + shellQuote(NODE) + ' ' + shellQuote(path.join(dir, 'cli.js')) + ' "$@"\n', { mode: 0o755 })
  console.log('  ✓ installed harness ' + entry.version + ' → ' + dir)
})().catch((err) => { console.error('✗ install failed: ' + err.message); process.exit(1) })
HARNESSJS

# 4. Ensure ~/.local/bin is on PATH (per shell), idempotently.
add_path_line='export PATH="$HOME/.local/bin:$PATH"'
marker='# added by harness installer'
ensure_rc() {
  rc="$1"
  [ -f "$rc" ] || : > "$rc"
  if ! grep -qF "$marker" "$rc" 2>/dev/null; then
    printf '\n%s\n%s\n' "$marker" "$add_path_line" >> "$rc"
    echo "  ✓ added ~/.local/bin to PATH in $rc"
  fi
}
case "$(basename "${SHELL:-/bin/sh}")" in
  zsh)  ensure_rc "$HOME/.zshrc" ;;
  # `.bashrc` alone is not enough. A LOGIN shell reads .bash_profile / .bash_login / .profile and never
  # .bashrc — that is `bash -lc`, `ssh host cmd`, most CI, and every `docker exec … bash -l`. On a
  # desktop or an ssh session the shell is interactive so .bashrc is read and the gap is invisible;
  # inside a container it means `harness` is never on PATH no matter how many new shells you open.
  # macOS already covered this by also writing .bash_profile (Terminal starts login shells); do the
  # same on Linux, writing whichever login file bash will actually consult — it reads the FIRST that
  # exists, so appending to a lower-priority one would be silently ignored.
  bash) ensure_rc "$HOME/.bashrc"
        if [ -f "$HOME/.bash_profile" ]; then ensure_rc "$HOME/.bash_profile"
        elif [ -f "$HOME/.bash_login" ]; then ensure_rc "$HOME/.bash_login"
        elif [ "$(uname)" = "Darwin" ]; then ensure_rc "$HOME/.bash_profile"
        else ensure_rc "$HOME/.profile"
        fi ;;
  fish) mkdir -p "$HOME/.config/fish"
        rc="$HOME/.config/fish/config.fish"; [ -f "$rc" ] || : > "$rc"
        grep -qF "$marker" "$rc" 2>/dev/null || printf '\n%s\nfish_add_path %s\n' "$marker" "$HOME/.local/bin" >> "$rc" ;;
  *)    ensure_rc "$HOME/.profile" ;;
esac

# 5. Final verification. Use the launcher by absolute path because this process cannot update its
#    parent shell's PATH. Installation never authenticates or starts the adapter implicitly.
"$NODE_BIN" --version >/dev/null 2>&1 || { echo "✗ Managed Node verification failed." >&2; exit 30; }
"$LAUNCHER" version >/dev/null 2>&1 || { echo "✗ Harness CLI verification failed." >&2; exit 31; }
if [ "$INSTALL_MODE" = "standalone" ]; then
  tmux -V >/dev/null 2>&1 || { echo "✗ tmux verification failed." >&2; exit 32; }
fi

# The explicit commands keep
#    browser SSO and long-lived daemon lifecycle understandable and scriptable.
echo ""
echo "  harness installed."
echo "  To connect this computer, run:"
echo "      harness login"
echo "      harness start"

# 6. Make `harness` usable by NAME. We already added ~/.local/bin to your rc for NEW terminals (step 4);
#    a piped `curl … | sh` can't touch the CURRENT shell's PATH, so print the one line that fixes it here
#    now — but ONLY when ~/.local/bin isn't already on PATH (many Linux distros add it), to avoid nagging.
case ":${PATH}:" in
  *":$BIN_DIR:"*) : ;;  # already on PATH → `harness` works immediately, nothing to do
  *)
    echo ""
    echo "  'harness' is installed in ~/.local/bin. To run it in THIS terminal now:"
    echo "      export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo "  New terminals already have it (or reload this one with:  exec \$SHELL)."
    ;;
esac
