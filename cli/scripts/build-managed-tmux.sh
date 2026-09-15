#!/usr/bin/env bash
# Build the managed tmux that `install.sh` downloads on a Mac that has no tmux and no Homebrew —
# the same idea as the managed Node under ~/.harness/runtime: one checksum-verified archive we
# publish, so obtaining tmux never needs a compiler, a package manager or a password on the user's
# computer. Homebrew was how tmux got built before, and Homebrew's installer needs the Apple
# developer tools, which cost a Terminal window, a 2 GB download and a ten-minute wait for a 1 MB
# binary. This runs that build ONCE, in CI, per version.
#
#   bash cli/scripts/build-managed-tmux.sh darwin-arm64 [out-dir]
#   bash cli/scripts/build-managed-tmux.sh darwin-x64   [out-dir]      # cross-built on an arm64 Mac
#
# Produces <out-dir>/tmux-<ver>-<platform>.tar.gz whose root is tmux-<ver>-<platform>/bin/tmux,
# plus the three upstream licences. libevent and ncurses are linked statically; libSystem stays
# dynamic, as every macOS binary's does. Needs the Command Line Tools HERE, and nowhere else.
#
# The three sources are pinned by version AND sha256: a moved tarball fails loudly rather than
# building something else. ncurses's unversioned `ncurses.tar.gz` is deliberately not used.
set -euo pipefail

PLATFORM="${1:-}"
OUT_DIR="${2:-$PWD/dist/tmux}"
case "$PLATFORM" in
  darwin-arm64) ARCH=arm64; HOST=aarch64-apple-darwin ;;
  darwin-x64)   ARCH=x86_64; HOST=x86_64-apple-darwin ;;
  *)
    echo "usage: $0 darwin-arm64|darwin-x64 [out-dir]" >&2
    exit 2
    ;;
esac
[ "$(uname -s)" = Darwin ] || { echo "error: the managed tmux is built on macOS" >&2; exit 1; }

TMUX_VERSION="${TMUX_VERSION:-3.7c}"
LIBEVENT_VERSION="${LIBEVENT_VERSION:-2.1.12-stable}"
NCURSES_VERSION="${NCURSES_VERSION:-6.5}"

# Pinned sources. Bumping a version means bumping its checksum in the same change.
LIBEVENT_URL="https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}/libevent-${LIBEVENT_VERSION}.tar.gz"
LIBEVENT_SHA256="${LIBEVENT_SHA256:-92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb}"
NCURSES_URL="https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"
NCURSES_SHA256="${NCURSES_SHA256:-136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6}"
TMUX_URL="https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"
TMUX_SHA256="${TMUX_SHA256:-7c60cae9a0e25288e2e24750aafc9e8800fc7fd4555e447e1b29ee4201cfb3bf}"

for command in curl tar shasum make cc codesign otool; do
  command -v "$command" >/dev/null 2>&1 || { echo "error: $command is required" >&2; exit 1; }
done
/usr/bin/xcrun --find clang >/dev/null 2>&1 || {
  echo "error: the Apple developer tools are required to BUILD tmux (never to install it)" >&2
  exit 1
}

# `--host` only when actually cross-compiling. Passing it for the native build flips autoconf into
# cross mode, where run-time feature tests are skipped and answered "no" — libevent then built a
# tmux that segfaulted in evutil_make_internal_pipe_ on the very Mac that built it.
NATIVE_ARCH="$(uname -m)"
[ "$NATIVE_ARCH" = arm64 ] && NATIVE_ARCH=arm64 || NATIVE_ARCH=x86_64
if [ "$ARCH" = "$NATIVE_ARCH" ]; then HOST_FLAG=""; else HOST_FLAG="--host=$HOST"; fi

WORK="$(mktemp -d)"
# KEEP_WORK=1 leaves the build tree behind for a post-mortem.
[ -n "${KEEP_WORK:-}" ] && echo ">> work dir: $WORK" || trap 'rm -rf "$WORK"' EXIT
ROOT="tmux-${TMUX_VERSION}-${PLATFORM}"
STAGE="$WORK/stage/$ROOT"
DEPS="$WORK/deps"
mkdir -p "$STAGE/bin" "$DEPS" "$OUT_DIR"
NPROC="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"

fetch() { # url sha256 name
  local archive="$WORK/$3.tar.gz" got
  echo ">> $3: downloading $1"
  curl -fsSL "$1" -o "$archive"
  got="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [ "$got" = "$2" ] || { echo "error: $3 checksum mismatch (expected $2, got $got)" >&2; exit 1; }
  mkdir -p "$WORK/src/$3"
  tar -xzf "$archive" -C "$WORK/src/$3" --strip-components=1
}
fetch "$LIBEVENT_URL" "$LIBEVENT_SHA256" libevent
fetch "$NCURSES_URL" "$NCURSES_SHA256" ncurses
fetch "$TMUX_URL" "$TMUX_SHA256" tmux

# One toolchain line for all three: the target arch (cross-built for x64 on an arm64 Mac) and a
# deployment target old enough for every Mac the app supports.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
# The /usr/bin shim resolves the SDK through xcrun; the toolchain's own clang does not, and links
# nothing without an explicit sysroot.
export SDKROOT="$(/usr/bin/xcrun --show-sdk-path)"
export CC=/usr/bin/clang
export CFLAGS="-arch $ARCH -O2 -isysroot $SDKROOT"
export LDFLAGS="-arch $ARCH -isysroot $SDKROOT -L$DEPS/lib"
export CPPFLAGS="-I$DEPS/include -I$DEPS/include/ncursesw"
# LIBDIR, not PATH: PATH is prepended to pkg-config's default search list, which on any Mac with
# Homebrew (every CI runner included) still finds /usr/local and /opt/homebrew — tmux 3.7 then
# linked an Intel Homebrew jemalloc. LIBDIR replaces the list, so only our own .pc files exist.
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"

echo ">> libevent $LIBEVENT_VERSION"
(
  cd "$WORK/src/libevent"
  # A current macOS SDK makes autoconf's link test for pipe2 succeed although macOS has no pipe2;
  # the resulting HAVE_PIPE2 sends evutil_make_internal_pipe_ through a null pointer on the first
  # new-session. Answered up front, then every Linux-only syscall is re-checked below.
  # shellcheck disable=SC2086
  ac_cv_func_pipe2=no ./configure $HOST_FLAG --prefix="$DEPS" --disable-shared --enable-static \
    --disable-openssl --disable-samples --disable-libevent-regress --disable-debug-mode >/dev/null
  if grep -Eq '^#define (EVENT__)?HAVE_(PIPE2|EPOLL|EVENTFD|TIMERFD|ACCEPT4|SIGNALFD|SPLICE)\b' config.h; then
    echo "error: libevent's configure detected a Linux-only call on macOS:" >&2
    grep -E '^#define (EVENT__)?HAVE_(PIPE2|EPOLL|EVENTFD|TIMERFD|ACCEPT4|SIGNALFD|SPLICE)\b' config.h >&2
    exit 1
  fi
  make -j"$NPROC" >/dev/null 2>&1
  make install >/dev/null
)

# ncurses: static, terminfo read from the macOS system database (tmux-256color is there on
# macOS 13+, screen-256color everywhere), so no `tic`, no bundled terminfo, no programs that would
# shadow /usr/bin/clear and friends.
echo ">> ncurses $NCURSES_VERSION"
(
  cd "$WORK/src/ncurses"
  # shellcheck disable=SC2086
  ./configure $HOST_FLAG --prefix="$DEPS" \
    --with-termlib --without-shared --with-normal --without-debug --without-ada \
    --without-progs --without-manpages --without-tests --without-cxx --without-cxx-binding \
    --enable-pc-files --with-pkg-config-libdir="$DEPS/lib/pkgconfig" \
    --with-default-terminfo-dir=/usr/share/terminfo \
    --with-terminfo-dirs=/usr/share/terminfo:/usr/lib/terminfo \
    --disable-db-install >/dev/null 2>&1
  make -j"$NPROC" >/dev/null 2>&1
  make install >/dev/null 2>&1
)

echo ">> tmux $TMUX_VERSION"
(
  cd "$WORK/src/tmux"
  # Named explicitly rather than left to pkg-config: ncurses 6 installs the wide-character
  # `tinfow`, tmux's configure asks pkg-config for `tinfo`, and on a miss it silently links the
  # system's ncurses 5.4 against our 6.5 headers — a binary that answers `-V` and then segfaults on
  # `new-session`. The .a files above are the only libraries at these paths, so the link is static
  # without any macOS-unfriendly -static flag.
  LIBEVENT_CORE_CFLAGS="-I$DEPS/include" LIBEVENT_CORE_LIBS="-L$DEPS/lib -levent_core" \
  LIBTINFO_CFLAGS="-I$DEPS/include -I$DEPS/include/ncursesw" LIBTINFO_LIBS="-L$DEPS/lib -ltinfow" \
  ./configure $HOST_FLAG --prefix="$STAGE" --disable-utf8proc --disable-jemalloc >/dev/null
  make -j"$NPROC" >/dev/null 2>&1
  cp tmux "$STAGE/bin/tmux"
  cp COPYING "$STAGE/LICENSE.tmux"
)
cp "$WORK/src/libevent/LICENSE" "$STAGE/LICENSE.libevent"
cp "$WORK/src/ncurses/COPYING" "$STAGE/LICENSE.ncurses"

# Ad-hoc signature (the linker adds one on arm64; make it explicit and identical for x64). Nothing
# here is notarized: curl sets no quarantine flag, so Gatekeeper never sees the binary.
codesign -s - --force "$STAGE/bin/tmux" 2>/dev/null

# The whole point: nothing but the OS may be needed at run time — no package-manager library (a
# Homebrew jemalloc, say), and not the system's ncurses 5.4 either (see the tmux configure note).
if otool -L "$STAGE/bin/tmux" | tail -n +2 | grep -Ev '^\s+/usr/lib/lib(System\.B|resolv\.9|util)\.dylib '; then
  echo "error: tmux links a library outside libSystem:" >&2
  otool -L "$STAGE/bin/tmux" >&2
  exit 1
fi

# Smoke test: version, then a real server on a private socket, under Rosetta for the x64 build.
run() {
  if [ "$ARCH" = x86_64 ] && [ "$(uname -m)" = arm64 ]; then arch -x86_64 "$@"; else "$@"; fi
}
run "$STAGE/bin/tmux" -V
SOCKET="$WORK/smoke.sock"
TERM=xterm-256color run "$STAGE/bin/tmux" -S "$SOCKET" -f /dev/null new-session -d -s smoke 'sleep 30'
run "$STAGE/bin/tmux" -S "$SOCKET" list-sessions | grep -q '^smoke:'
run "$STAGE/bin/tmux" -S "$SOCKET" kill-server

ARCHIVE="$OUT_DIR/$ROOT.tar.gz"
tar -czf "$ARCHIVE" -C "$WORK/stage" "$ROOT"
echo ">> built $ARCHIVE ($(wc -c < "$ARCHIVE" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$ARCHIVE" | awk '{print $1}'))"
