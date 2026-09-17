#!/usr/bin/env bash
# A new Builder workspace (cwd): the build record and the first verdict, so the pane header and
# Builder Studio have a state before the first prompt.
set -euo pipefail
HARNESS_WORKSPACE="$PWD" exec "$(dirname "$0")/builder" init
