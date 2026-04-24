#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export RUST_LOG="${RUST_LOG:-vish=debug,vishd=debug,info}"
export RUST_BACKTRACE=1
cargo run -p vish "$@"
